//
//  FindSymbolDefinitionToolTests.swift
//  SwiftMCPServerTests
//
//  Created by k2moons on 2026/05/16.
//
//  [Code Header Format]
//
//  目的
//  - FindSymbolDefinitionTool（DES-104 §6 / §11.2）の挙動を網羅する単体テスト
//  - symbol_kinds 種別フィルタ（未指定 / 単一 / 複数 OR）の正常系を検証
//  - parent_scope / extension_target / module_name の付与とスコープ区別を検証
//  - 異常系（未定義種別 / 部分的不正 / 配列要素数上限超過 / 空シンボル名）を検証
//
//  主要機能
//  - 一時 SwiftPM プロジェクトに Swift fixture を配置し execute を直接呼び出して結果を検証
//  - structured ブロック JSON の symbols / parent_scope / extension_target / module_name 判定
//  - 統一エラー応答（[Error] cause / suggestion）の文言検証
//
//  関連型
//  - FindSymbolDefinitionTool, SymbolKindMapper, ResultEncoder, ProjectMemory
//

import XCTest
import Foundation
import MCP
import Logging
@testable import Swift_Selena

final class FindSymbolDefinitionToolTests: XCTestCase {

    // MARK: - テストフィクスチャ

    private var tempProjectDir: URL!
    private var clientId: String!
    private var projectMemory: ProjectMemory!
    private var savedClientIdEnv: String?
    private let logger = Logger(label: "FindSymbolDefinitionToolTests")

    override func setUp() async throws {
        try await super.setUp()

        // 既存の MCP_CLIENT_ID を保存（tearDown で復元するため）
        // テスト実行前に外部（シェル export / CI ジョブ等）で設定された値を破壊しない
        if let prev = getenv("MCP_CLIENT_ID") {
            savedClientIdEnv = String(cString: prev)
        } else {
            savedClientIdEnv = nil
        }

        // クライアント ID を UUID で一意化（ProjectMemory のキャッシュを衝突させない）
        clientId = UUID().uuidString
        setenv("MCP_CLIENT_ID", clientId, 1)

        // 一時プロジェクトディレクトリを作成（SwiftPM 構造で module_name 解決を有効化）
        tempProjectDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("find_symbol_definition_tool_tests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempProjectDir,
            withIntermediateDirectories: true
        )

        // fixture を配置
        try writeFixtures()

        // ProjectMemory を生成
        projectMemory = try ProjectMemory(projectPath: tempProjectDir.path)
    }

    override func tearDown() async throws {
        // 一時プロジェクトディレクトリを削除
        if let dir = tempProjectDir {
            try? FileManager.default.removeItem(at: dir)
        }

        // ProjectMemory のキャッシュ（~/.swift-selena/clients/{uuid}/）を削除
        if let id = clientId {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            let clientDir = homeDir
                .appendingPathComponent(AppConstants.storageDirectory)
                .appendingPathComponent("clients")
                .appendingPathComponent(id)
            try? FileManager.default.removeItem(at: clientDir)
        }

        // MCP_CLIENT_ID を save-then-restore: 前値があれば復元、なければ削除
        if let prev = savedClientIdEnv {
            setenv("MCP_CLIENT_ID", prev, 1)
        } else {
            unsetenv("MCP_CLIENT_ID")
        }
        try await super.tearDown()
    }

    // MARK: - fixture 配置ヘルパー

    /// SwiftPM 構造で複数の Swift fixture を書き出す
    /// - Mixed: ルート型と関数・変数（種別未指定時の優先返却検証用）
    /// - Scopes: ルート Button / ネスト Foo.Button / extension Bar.Button（スコープ区別検証用）
    private func writeFixtures() throws {
        // SwiftPM 構造（Package.swift により module_name=MyTarget が解決される）
        try writeFile(relativePath: "Package.swift", content: """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(name: "MyTarget", targets: [.target(name: "MyTarget", path: "Sources/MyTarget")])
        """)

        // 種別フィルタ・優先返却検証用ファイル（同名 Sample で 9 区分中の複数を網羅）
        // 注: typealias / extension は同名で複数定義できないため、Sample(struct) と
        // extension Sample（kind=Extension で name=Sample）が同居する形にする
        try writeFile(relativePath: "Sources/MyTarget/Mixed.swift", content: """
        struct Sample {}
        class Sample_Class {}
        enum Sample_Enum {}
        protocol Sample_Protocol {}
        actor Sample_Actor {}
        extension Sample {}
        """)

        // 同名 Sample で複数種別が並ぶ fixture（multipleFilter / priority 検証用）
        // 1 ファイル内で同名宣言は衝突するため、別ファイルに class Sample / protocol Sample / func Sample / var Sample を配置する
        try writeFile(relativePath: "Sources/MyTarget/SampleClass.swift", content: """
        class Sample {}
        """)
        try writeFile(relativePath: "Sources/MyTarget/SampleProtocol.swift", content: """
        protocol Sample {}
        """)
        try writeFile(relativePath: "Sources/MyTarget/SampleFunction.swift", content: """
        func Sample() {}
        """)
        try writeFile(relativePath: "Sources/MyTarget/SampleVariable.swift", content: """
        var Sample: Int = 0
        """)
        // DES-104 §11.2 受入基準「symbol_kinds 未指定時、全 9 区分が返る」を検証するため、
        // 残り 3 区分（Enum / Actor / TypeAlias）も同名 Sample で配置する
        try writeFile(relativePath: "Sources/MyTarget/SampleEnum.swift", content: """
        enum Sample {}
        """)
        try writeFile(relativePath: "Sources/MyTarget/SampleActor.swift", content: """
        actor Sample {}
        """)
        try writeFile(relativePath: "Sources/MyTarget/SampleTypeAlias.swift", content: """
        typealias Sample = Int
        """)

        // スコープ区別検証用（ルート / ネスト / extension）
        try writeFile(relativePath: "Sources/MyTarget/Scopes.swift", content: """
        struct Button {}
        enum Foo {
            struct Button {}
        }
        extension Bar {
            struct Button {}
        }
        """)
    }

    private func writeFile(relativePath: String, content: String) throws {
        let fileURL = tempProjectDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - 実行ヘルパー

    /// 引数辞書から CallTool.Parameters を作成し FindSymbolDefinitionTool を実行する
    private func runFindSymbolDefinition(arguments: [String: Value]) async throws -> String {
        let params = CallTool.Parameters(
            name: ToolNames.findSymbolDefinition,
            arguments: arguments
        )
        let result = try await FindSymbolDefinitionTool.execute(
            params: params,
            projectMemory: projectMemory,
            logger: logger
        )
        // 最初の .text コンテンツを文字列として取り出す
        for content in result.content {
            if case .text(let text, _, _) = content {
                return text
            }
        }
        XCTFail("CallTool.Result に text コンテンツが含まれていません")
        return ""
    }

    /// 応答文字列を `--- structured ---` で分割する。json 部が無い場合 nil
    private func splitStructured(_ response: String) -> (text: String, json: String?) {
        let separator = "\n--- structured ---\n"
        guard let range = response.range(of: separator) else {
            return (response, nil)
        }
        let text = String(response[..<range.lowerBound])
        let json = String(response[range.upperBound...])
        return (text, json)
    }

    /// JSON 文字列を辞書としてパース
    private func parseJSON(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - 正常系: 優先返却順（symbol_kinds 未指定）

    /// 種別未指定時は優先返却対象（Class/Struct/Enum/Protocol/Actor）が
    /// 非優先返却対象（Function/Variable/TypeAlias/Extension）より先に並ぶ
    func test_symbolKindsUnspecified_returnsPriorityGroupFirst() async throws {
        let response = try await runFindSymbolDefinition(arguments: [
            ParameterKeys.symbolName: .string("Sample"),
        ])
        let parts = splitStructured(response)

        guard let json = parts.json.flatMap(parseJSON),
              let symbols = json["symbols"] as? [[String: Any]] else {
            return XCTFail("structured JSON / symbols が取得できない")
        }
        XCTAssertFalse(symbols.isEmpty, "Sample シンボルが少なくとも 1 件は検出されるはず")

        // 優先返却対象（priorityGroup=0）が出現する最後の位置と
        // 非優先返却対象（priorityGroup=1）が出現する最初の位置を比較
        let priorityGroup0Kinds: Set<String> = ["Class", "Struct", "Enum", "Protocol", "Actor"]
        let priorityGroup1Kinds: Set<String> = ["Function", "Variable", "TypeAlias", "Extension"]

        var lastIndexOfGroup0: Int = -1
        var firstIndexOfGroup1: Int = Int.max
        for (index, sym) in symbols.enumerated() {
            guard let kind = sym["kind"] as? String else { continue }
            if priorityGroup0Kinds.contains(kind) {
                lastIndexOfGroup0 = index
            }
            if priorityGroup1Kinds.contains(kind), index < firstIndexOfGroup1 {
                firstIndexOfGroup1 = index
            }
        }
        // 両グループとも検出されている前提（fixture により担保）
        XCTAssertNotEqual(lastIndexOfGroup0, -1, "優先返却対象（型宣言）が少なくとも 1 件あるはず")
        XCTAssertNotEqual(firstIndexOfGroup1, Int.max, "非優先返却対象（関数・変数等）が少なくとも 1 件あるはず")
        XCTAssertLessThan(lastIndexOfGroup0, firstIndexOfGroup1,
                          "優先返却対象（型宣言）が非優先返却対象より先に並ぶ")

        // DES-104 §11.2 受入基準: symbol_kinds 未指定時は全 9 区分が返る
        // 一部 kind が欠落するリグレッションを検出するため、返却された kind 集合が
        // 期待 9 区分を包含することを Set 比較で検証する
        let expectedKinds: Set<String> = [
            "Struct", "Class", "Enum", "Protocol", "Actor",
            "Function", "Variable", "TypeAlias", "Extension",
        ]
        let actualKinds = Set(symbols.compactMap { $0["kind"] as? String })
        XCTAssertEqual(
            actualKinds.intersection(expectedKinds), expectedKinds,
            "DES-104 §11.2: symbol_kinds 未指定時は全 9 区分が返るはず（不足: \(expectedKinds.subtracting(actualKinds))）"
        )
    }

    // MARK: - 正常系: 単一指定フィルタ

    /// symbol_kinds: ["struct"] 指定時、Struct のシンボルのみ返る
    func test_symbolKinds_singleFilter_returnsOnlyMatchingKind() async throws {
        let response = try await runFindSymbolDefinition(arguments: [
            ParameterKeys.symbolName: .string("Sample"),
            ParameterKeys.symbolKinds: .array([.string("struct")]),
        ])
        let parts = splitStructured(response)

        guard let json = parts.json.flatMap(parseJSON),
              let symbols = json["symbols"] as? [[String: Any]] else {
            return XCTFail("structured JSON / symbols が取得できない")
        }
        XCTAssertFalse(symbols.isEmpty, "Struct Sample が検出されるはず")
        for sym in symbols {
            XCTAssertEqual(sym["kind"] as? String, "Struct",
                           "single filter='struct' は Struct のみ返す")
        }
    }

    // MARK: - 正常系: 複数指定フィルタ（OR）

    /// symbol_kinds: ["class", "protocol"] 指定時、Class と Protocol のみ OR で返る
    func test_symbolKinds_multipleFilter_returnsORedKinds() async throws {
        let response = try await runFindSymbolDefinition(arguments: [
            ParameterKeys.symbolName: .string("Sample"),
            ParameterKeys.symbolKinds: .array([.string("class"), .string("protocol")]),
        ])
        let parts = splitStructured(response)

        guard let json = parts.json.flatMap(parseJSON),
              let symbols = json["symbols"] as? [[String: Any]] else {
            return XCTFail("structured JSON / symbols が取得できない")
        }

        // fixture には class Sample / protocol Sample / struct Sample 等 同名 Sample で
        // 複数種別が存在する。filter=['class','protocol'] では Class と Protocol のみ
        // 返り、Struct/Function/Variable/Extension は除外される（OR 結合かつ非対象は除外）。
        XCTAssertFalse(symbols.isEmpty, "symbols が空でないはず（class/protocol いずれかは検出される）")
        var hasClass = false
        var hasProtocol = false
        for sym in symbols {
            guard let kind = sym["kind"] as? String else { continue }
            XCTAssertTrue(kind == "Class" || kind == "Protocol",
                          "multi filter=['class','protocol'] では Class/Protocol 以外含まれない（実際の kind=\(kind)）")
            if kind == "Class" { hasClass = true }
            if kind == "Protocol" { hasProtocol = true }
        }
        XCTAssertTrue(hasClass, "OR 結合で Class Sample が返るはず")
        XCTAssertTrue(hasProtocol, "OR 結合で Protocol Sample が返るはず")
    }

    // MARK: - 正常系: ルート / ネスト / extension の区別

    /// ルート直下の型は parent_scope=nil（NSNull が JSON では null として現れる）
    func test_rootLevelType_hasNilParentScope() async throws {
        let response = try await runFindSymbolDefinition(arguments: [
            ParameterKeys.symbolName: .string("Button"),
            ParameterKeys.symbolKinds: .array([.string("struct")]),
        ])
        let parts = splitStructured(response)

        guard let json = parts.json.flatMap(parseJSON),
              let symbols = json["symbols"] as? [[String: Any]] else {
            return XCTFail("structured JSON / symbols が取得できない")
        }

        // ルート Button: parent_scope=null かつ extension_target=null
        let rootButton = symbols.first(where: { sym in
            sym["parent_scope"] is NSNull && sym["extension_target"] is NSNull
        })
        XCTAssertNotNil(rootButton, "ルート定義の Button（parent_scope=null, extension_target=null）が存在するはず")
    }

    /// ネスト型は parent_scope に親型名
    func test_nestedType_hasParentScopePopulated() async throws {
        let response = try await runFindSymbolDefinition(arguments: [
            ParameterKeys.symbolName: .string("Button"),
            ParameterKeys.symbolKinds: .array([.string("struct")]),
        ])
        let parts = splitStructured(response)

        guard let json = parts.json.flatMap(parseJSON),
              let symbols = json["symbols"] as? [[String: Any]] else {
            return XCTFail("structured JSON / symbols が取得できない")
        }

        let nestedButton = symbols.first(where: { ($0["parent_scope"] as? String) == "Foo" })
        XCTAssertNotNil(nestedButton, "ネスト型 Foo.Button（parent_scope='Foo'）が存在するはず")
        // ネスト型は extension_target が null
        XCTAssertTrue(nestedButton?["extension_target"] is NSNull,
                      "ネスト型は extension_target=null")
    }

    /// extension 内の型は extension_target に対象型名
    func test_extensionInnerType_hasExtensionTargetPopulated() async throws {
        let response = try await runFindSymbolDefinition(arguments: [
            ParameterKeys.symbolName: .string("Button"),
            ParameterKeys.symbolKinds: .array([.string("struct")]),
        ])
        let parts = splitStructured(response)

        guard let json = parts.json.flatMap(parseJSON),
              let symbols = json["symbols"] as? [[String: Any]] else {
            return XCTFail("structured JSON / symbols が取得できない")
        }

        let extButton = symbols.first(where: { ($0["extension_target"] as? String) == "Bar" })
        XCTAssertNotNil(extButton, "extension Bar 内の Button（extension_target='Bar'）が存在するはず")
        // extension 直下の型は parent_scope が null（DES-104 §4.5 決定規則）
        XCTAssertTrue(extButton?["parent_scope"] is NSNull,
                      "extension 直下の型は parent_scope=null")
    }

    // MARK: - 異常系: 未定義種別

    /// symbol_kinds=["unknown_type"] → エラー（cause/suggestion 文言を含む）
    func test_unknownSymbolKind_returnsInvalidParamsError() async throws {
        let response = try await runFindSymbolDefinition(arguments: [
            ParameterKeys.symbolName: .string("Sample"),
            ParameterKeys.symbolKinds: .array([.string("unknown_type")]),
        ])
        XCTAssertTrue(response.hasPrefix("[Error]"), "エラーは [Error] で始まる")
        XCTAssertTrue(response.contains("cause:"), "cause: を含む")
        XCTAssertTrue(response.contains("suggestion:"), "suggestion: を含む")
        XCTAssertTrue(response.contains(ErrorMessages.symbolKindUndefinedCause),
                      "未定義種別の cause 文言を含む")
        XCTAssertTrue(response.contains("unknown_type"),
                      "無効な値（unknown_type）がエラーメッセージに列挙される")
    }

    // MARK: - 異常系: 部分的不正値

    /// symbol_kinds=["struct","invalid_kind"] → 部分的無視せずエラー
    func test_partiallyInvalidKinds_returnsError() async throws {
        let response = try await runFindSymbolDefinition(arguments: [
            ParameterKeys.symbolName: .string("Sample"),
            ParameterKeys.symbolKinds: .array([.string("struct"), .string("invalid_kind")]),
        ])
        XCTAssertTrue(response.hasPrefix("[Error]"), "一部不正でもエラー（部分的無視は行わない）")
        XCTAssertTrue(response.contains(ErrorMessages.symbolKindUndefinedCause),
                      "未定義種別の cause 文言を含む")
        XCTAssertTrue(response.contains("invalid_kind"),
                      "不正値（invalid_kind）がエラーメッセージに列挙される")
    }

    // MARK: - 異常系: 配列要素数上限超過

    /// symbol_kinds に 10 件以上（重複含む）→ 上限超過エラー（DES-104 §2 TBD-009 上限=9）
    func test_symbolKindsExceedsMaxCount_returnsError() async throws {
        // 9 区分 + 重複 1 件 = 10 件で上限超過
        let kinds: [Value] = [
            .string("struct"), .string("class"), .string("enum"),
            .string("protocol"), .string("actor"), .string("function"),
            .string("variable"), .string("typealias"), .string("extension"),
            .string("struct"), // 重複で 10 件目（上限 9 件超過）
        ]
        let response = try await runFindSymbolDefinition(arguments: [
            ParameterKeys.symbolName: .string("Sample"),
            ParameterKeys.symbolKinds: .array(kinds),
        ])
        XCTAssertTrue(response.hasPrefix("[Error]"), "エラーは [Error] で始まる")
        XCTAssertTrue(response.contains(ErrorMessages.arrayCountExceededCause),
                      "配列要素数上限超過の cause を含む")
    }

    // MARK: - 異常系: 空シンボル名

    /// symbol_name="" → エラー（DES-104 §8.1 形式）
    func test_emptySymbolName_returnsError() async throws {
        let response = try await runFindSymbolDefinition(arguments: [
            ParameterKeys.symbolName: .string(""),
        ])
        XCTAssertTrue(response.hasPrefix("[Error]"), "エラーは [Error] で始まる")
        XCTAssertTrue(response.contains("cause:"), "cause: を含む")
        XCTAssertTrue(response.contains("suggestion:"), "suggestion: を含む")
    }

    // MARK: - 構造化出力検証

    /// 構造化結果に parent_scope / extension_target / module_name が含まれる
    func test_structuredOutput_containsScopeInfo() async throws {
        let response = try await runFindSymbolDefinition(arguments: [
            ParameterKeys.symbolName: .string("Button"),
            ParameterKeys.symbolKinds: .array([.string("struct")]),
        ])
        let parts = splitStructured(response)

        XCTAssertNotNil(parts.json, "--- structured --- セクションが含まれる")
        guard let json = parts.json.flatMap(parseJSON),
              let symbols = json["symbols"] as? [[String: Any]] else {
            return XCTFail("structured JSON / symbols が取得できない")
        }
        XCTAssertFalse(symbols.isEmpty, "シンボルが少なくとも 1 件返るはず")

        for sym in symbols {
            XCTAssertNotNil(sym["parent_scope"], "各シンボルが parent_scope フィールドを持つ")
            XCTAssertNotNil(sym["extension_target"], "各シンボルが extension_target フィールドを持つ")
            XCTAssertNotNil(sym["module_name"], "各シンボルが module_name フィールドを持つ")
        }

        // SwiftPM 構造の fixture により module_name=MyTarget が解決されているか確認
        let hasMyTargetModule = symbols.contains(where: { ($0["module_name"] as? String) == "MyTarget" })
        XCTAssertTrue(hasMyTargetModule, "SwiftPM 構造の fixture から module_name='MyTarget' が解決されるはず")
    }
}
