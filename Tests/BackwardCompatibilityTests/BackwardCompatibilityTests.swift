//
//  BackwardCompatibilityTests.swift
//  SwiftMCPServerTests
//
//  Created by k2moons on 2026/05/16.
//
//  [Code Header Format]
//
//  目的
//  - DES-104 §11.4 / REQ-005 §4.6 の後方互換テストを単体テストとして網羅する
//  - search_code / find_symbol_definition の既存テキスト出力契約が維持されていることを検証
//  - file_pattern 廃止が破壊的変更として許容済みである旨をテスト名・コメントで明示する
//  - cacheVersion 3→4 マイグレーション時に v3 キャッシュが全破棄され空再構築されることを検証
//
//  主要機能
//  - 一時プロジェクトに Swift fixture を配置し各ツールを直接実行して出力契約を検証
//  - 行頭フォーマット <file>:<line>: <content> および [Kind] Name / File / Line の機械的検証
//  - --- structured --- 以降の付加が既存テキスト行を改変しないことの検証
//  - v3 形式 memory.json fixture を投入し ProjectMemory 再初期化後にキャッシュが空になることの検証
//
//  関連型
//  - SearchCodeTool, FindSymbolDefinitionTool, ProjectMemory, ResultEncoder
//

import XCTest
import Foundation
import CryptoKit
import MCP
import Logging
@testable import Swift_Selena

final class BackwardCompatibilityTests: XCTestCase {

    // MARK: - テストフィクスチャ

    private var tempProjectDir: URL!
    private var clientId: String!
    private var projectMemory: ProjectMemory!
    private var savedClientIdEnv: String?
    private let logger = Logger(label: "BackwardCompatibilityTests")

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

        // 一時プロジェクトディレクトリを作成
        tempProjectDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("backward_compat_tests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempProjectDir,
            withIntermediateDirectories: true
        )

        // fixture を配置
        try writeFixtures()

        // ProjectMemory を生成（環境変数 MCP_CLIENT_ID に従ってキャッシュ先が分離される）
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

    /// 後方互換検証で参照する典型的な Swift fixture を配置する
    /// - search_code（pattern のみ）でマッチする `hello` を含む複数ファイル
    /// - find_symbol_definition で複数 kind が並ぶ Sample
    private func writeFixtures() throws {
        // SwiftPM 構造（module_name 解決を有効化）
        try writeFile(relativePath: "Package.swift", content: """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(name: "MyTarget", targets: [.target(name: "MyTarget", path: "Sources/MyTarget")])
        """)

        try writeFile(relativePath: "Sources/MyTarget/Foo.swift", content: """
        struct Foo {
            func hello() { print("hello") }
            func world() { print("world") }
        }
        """)
        try writeFile(relativePath: "Sources/MyTarget/Bar.swift", content: """
        struct Bar {
            func hello() { print("hello bar") }
        }
        """)

        // 種別フィルタ未指定でも複数 kind が並ぶように同名 Sample を別ファイルで配置
        try writeFile(relativePath: "Sources/MyTarget/Sample.swift", content: """
        struct Sample {}
        """)
        try writeFile(relativePath: "Sources/MyTarget/SampleClass.swift", content: """
        class Sample {}
        """)

        // file_pattern 廃止テスト用: hello を含む .md ファイルを 1 件配置する
        // fixture に .md が存在しないと、file_pattern="*.md" が誤って効いた場合と
        // 効いていない場合の結果（files に .md が無い .swift のみ）が同一になり、
        // 破壊的変更（REQ-005 §4.6）の回帰検出が機能しないため
        try writeFile(relativePath: "Sources/MyTarget/README.md", content: """
        hello in markdown (must be ignored because file_pattern is removed)
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

    /// 引数辞書から CallTool.Parameters を作成し SearchCodeTool を実行する
    private func runSearchCode(arguments: [String: Value]) async throws -> String {
        let params = CallTool.Parameters(
            name: ToolNames.searchCode,
            arguments: arguments
        )
        let result = try await SearchCodeTool.execute(
            params: params,
            projectMemory: projectMemory,
            logger: logger
        )
        for content in result.content {
            if case .text(let text, _, _) = content {
                return text
            }
        }
        XCTFail("CallTool.Result に text コンテンツが含まれていません")
        return ""
    }

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

    // MARK: - search_code 出力契約テスト（DES-104 §11.4 / §9.1）

    /// pattern のみを指定した既存呼び出しで、各マッチ行が `<file>:<line>: <content>` 形式である（DES-104 §11.4）
    ///
    /// REQ-005 §4.6 後方互換: 既存テキスト出力の行頭フォーマット
    /// `<file>:<line>: <content>` は破壊的変更の許容範囲外であり維持される。
    func test_searchCode_legacyMatchDetail_lineFormatUnchanged() async throws {
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
        ])
        let parts = splitStructured(response)

        // 既存ヘッダ行（マッチ件数）
        XCTAssertTrue(
            parts.text.hasPrefix("Found "),
            "従来どおり 'Found N matches:' ヘッダで始まる"
        )

        // マッチ行は `<absolutePath>:<line>: <content>` 形式（前後空白除去済み）
        // 行頭フォーマット検証用の正規表現:
        //   ^/[^:]+:[0-9]+: .+
        // - 絶対パス（先頭 /、コロンを含まない）
        // - コロン区切りで行番号
        // - コロン+半角スペース 1 個の後にマッチ行内容
        let lineFormatRegex = try NSRegularExpression(
            pattern: #"^/[^:]+:[0-9]+: .+"#,
            options: []
        )

        let lines = parts.text.components(separatedBy: "\n")
        // マッチ行のみ抽出（ヘッダ + 空行 + Truncated 行を除外）
        let matchLines = lines.filter { line in
            !line.isEmpty
                && !line.hasPrefix("Found ")
                && !line.hasPrefix("[Truncated")
        }
        XCTAssertFalse(matchLines.isEmpty, "少なくとも 1 件のマッチ行があるはず")

        for matchLine in matchLines {
            let range = NSRange(matchLine.startIndex..., in: matchLine)
            XCTAssertNotNil(
                lineFormatRegex.firstMatch(in: matchLine, range: range),
                "マッチ行が '<file>:<line>: <content>' 形式に一致しない: \(matchLine)"
            )
        }
    }

    /// 既存テキスト行はそのまま保持され、`--- structured ---` 以降に JSON が付加される（DES-104 §9.1）
    ///
    /// REQ-005 §4.6: 追加情報は新規行・新規ブロック・末尾セクションとしてのみ許容される。
    func test_searchCode_structuredBlockAppendedAfterLegacyLines() async throws {
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
        ])

        // separator が応答末尾セクションとして 1 度だけ現れる
        let separator = "\n--- structured ---\n"
        let separatorCount = response.components(separatedBy: separator).count - 1
        XCTAssertEqual(
            separatorCount,
            1,
            "応答中に '--- structured ---' セクションが 1 度だけ現れる"
        )

        let parts = splitStructured(response)
        // テキスト部の各行は従来フォーマットの形を保つ（separator 以降に新規区切り混在なし）
        XCTAssertFalse(
            parts.text.contains("--- structured ---"),
            "テキスト部に separator が混入していない"
        )
        // JSON 部は有効な JSON 構造
        guard let json = parts.json, let data = json.data(using: .utf8) else {
            return XCTFail("structured JSON が取得できない")
        }
        XCTAssertNoThrow(
            try JSONSerialization.jsonObject(with: data),
            "--- structured --- 以降が有効な JSON"
        )
    }

    // MARK: - find_symbol_definition 出力契約テスト（DES-104 §11.4 / §9.2）

    /// 既存の `[Kind] Name` / `  File: ...` / `  Line: ...` 形式が維持される（DES-104 §9.2）
    ///
    /// REQ-005 §4.6 後方互換: 出力テキストの先頭部分 `[Kind] Name / File: / Line:` は変更されない。
    /// `Scope:` 行のみが追加行として付与される。
    func test_findSymbolDefinition_legacyTextFormatUnchanged() async throws {
        let response = try await runFindSymbolDefinition(arguments: [
            ParameterKeys.symbolName: .string("Sample"),
        ])
        let parts = splitStructured(response)

        // ヘッダ行: Found N definition(s) for 'Sample':
        XCTAssertTrue(
            parts.text.hasPrefix("Found "),
            "従来どおり 'Found N definition(s) for' ヘッダで始まる"
        )
        XCTAssertTrue(
            parts.text.contains("definition(s) for 'Sample'"),
            "シンボル名がヘッダに含まれる"
        )

        // [Kind] Name 行 / File: 行 / Line: 行が含まれる
        let lines = parts.text.components(separatedBy: "\n")

        // [Kind] Name 形式: 先頭が `[` で `]` を含み Name が後続
        let kindLineRegex = try NSRegularExpression(
            pattern: #"^\[[A-Za-z]+\] \S+"#,
            options: []
        )
        // File 行: `  File: /...`
        let fileLineRegex = try NSRegularExpression(
            pattern: #"^  File: /.+"#,
            options: []
        )
        // Line 行: `  Line: <number>`
        let lineLineRegex = try NSRegularExpression(
            pattern: #"^  Line: [0-9]+$"#,
            options: []
        )

        var kindLineCount = 0
        var fileLineCount = 0
        var lineLineCount = 0
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if kindLineRegex.firstMatch(in: line, range: range) != nil {
                kindLineCount += 1
            }
            if fileLineRegex.firstMatch(in: line, range: range) != nil {
                fileLineCount += 1
            }
            if lineLineRegex.firstMatch(in: line, range: range) != nil {
                lineLineCount += 1
            }
        }
        XCTAssertGreaterThan(kindLineCount, 0, "[Kind] Name 行が少なくとも 1 件あるはず")
        XCTAssertEqual(
            kindLineCount,
            fileLineCount,
            "[Kind] Name の件数と File: 行の件数が一致する"
        )
        XCTAssertEqual(
            kindLineCount,
            lineLineCount,
            "[Kind] Name の件数と Line: 行の件数が一致する"
        )
    }

    /// 既存テキスト行はそのまま保持され、`--- structured ---` 以降に構造化 JSON が付加される（DES-104 §9.2）
    func test_findSymbolDefinition_structuredBlockAppendedAfterLegacyLines() async throws {
        let response = try await runFindSymbolDefinition(arguments: [
            ParameterKeys.symbolName: .string("Sample"),
        ])

        // separator が応答末尾セクションとして 1 度だけ現れる
        let separator = "\n--- structured ---\n"
        let separatorCount = response.components(separatedBy: separator).count - 1
        XCTAssertEqual(
            separatorCount,
            1,
            "応答中に '--- structured ---' セクションが 1 度だけ現れる"
        )

        let parts = splitStructured(response)
        XCTAssertFalse(
            parts.text.contains("--- structured ---"),
            "テキスト部に separator が混入していない"
        )

        // 既存テキスト部の行頭は [Kind] / File: / Line: / Scope: のいずれか、または header / 空行
        // 既存契約に存在しない区切り（例: ;）や混在トークンが入っていないことを確認
        let lines = parts.text.components(separatedBy: "\n")
        for line in lines {
            if line.isEmpty { continue }
            if line.hasPrefix("Found ") { continue }
            if line.hasPrefix("[") { continue }
            if line.hasPrefix("  File: ") { continue }
            if line.hasPrefix("  Line: ") { continue }
            if line.hasPrefix("  Scope: ") { continue }
            XCTFail("既存契約外のテキスト行が混入: \(line)")
        }

        // JSON 部は有効な JSON
        guard let json = parts.json, let data = json.data(using: .utf8) else {
            return XCTFail("structured JSON が取得できない")
        }
        XCTAssertNoThrow(
            try JSONSerialization.jsonObject(with: data),
            "--- structured --- 以降が有効な JSON"
        )
    }

    // MARK: - file_pattern 廃止テスト（破壊的変更明示／REQ-005 §4.6 / §4.3）

    /// `file_pattern` パラメータは REQ-005 §4.6 で許容済みの破壊的変更として廃止された
    ///
    /// REQ-005 §4.6「破壊的変更（許容する範囲）」:
    ///   §4.3 `file_pattern` パラメータの廃止のみを許容する破壊的変更とする
    ///
    /// DES-104 §5.1: `file_pattern` キーが指定された場合の挙動は
    ///   **未知パラメータとして無視する**（`InvalidParams` エラーは返さない）
    ///
    /// 本テストは現在の実装挙動（無視されて既定挙動が適用される）を機械的に検証する。
    /// テスト名で REQ-005 §4.6 を明示し、破壊的変更が許容済みであることを記録する。
    func test_searchCode_filePatternParameterIsRemoved_breakingChange_REQ005_section46() async throws {
        // file_pattern="*.md" を渡しても無視され、include_patterns 未指定なら既定挙動（.swift 全体）が適用される
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.outputMode: .string("file_list"),
            "file_pattern": .string("*.md"),
        ])

        // エラー応答ではない（DES-104 §5.1 未知パラメータ無視方針）
        XCTAssertFalse(
            response.hasPrefix("[Error]"),
            "file_pattern 指定で InvalidParams は返さない（未知パラメータとして無視）"
        )

        // structured JSON を取り出して file_pattern が効いていないことを確認
        let parts = splitStructured(response)
        guard let jsonString = parts.json,
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [String] else {
            return XCTFail("structured JSON / files が取得できない")
        }
        // files が空配列だと allSatisfy が vacuous truth で偽陽性になるため、
        // 廃止契約検証の前に非空であることを保証する（fixture に hello を含む
        // .swift / .md を配置済みなので、既定挙動なら .swift が必ず 1 件以上返る）
        XCTAssertFalse(
            files.isEmpty,
            "既定挙動で .swift ファイルが少なくとも 1 件返るはず（空だと allSatisfy が vacuous truth で偽陽性になる）"
        )
        XCTAssertFalse(
            files.contains(where: { $0.hasSuffix(".md") }),
            "file_pattern は廃止済みのため '*.md' は対象外（破壊的変更：REQ-005 §4.6）"
        )
        // 既定挙動: .swift ファイルが対象として走査される
        XCTAssertTrue(
            files.allSatisfy { $0.hasSuffix(".swift") },
            "file_pattern 廃止後は include_patterns 未指定で .swift 既定挙動のみ"
        )
    }

    // MARK: - search_files_without_pattern 入力契約テスト（issue #34）

    /// 引数辞書から CallTool.Parameters を作成し SearchFilesWithoutPatternTool を実行する
    private func runSearchFilesWithoutPattern(arguments: [String: Value]) async throws -> String {
        let params = CallTool.Parameters(
            name: ToolNames.searchFilesWithoutPattern,
            arguments: arguments
        )
        let result = try await SearchFilesWithoutPatternTool.execute(
            params: params,
            projectMemory: projectMemory,
            logger: logger
        )
        for content in result.content {
            if case .text(let text, _, _) = content {
                return text
            }
        }
        XCTFail("CallTool.Result に text コンテンツが含まれていません")
        return ""
    }

    /// `file_pattern` パラメータは issue #34 で `search_code` と同じ理由により廃止された
    ///
    /// 旧仕様: `file_pattern: String?` で単一 glob を受け付け
    /// 新仕様: `include_patterns` / `exclude_patterns` の配列を受け付け
    /// 互換挙動: 旧キー `file_pattern` を指定しても未知パラメータとして無視され、既定挙動（`.swift` のみ）が適用される
    func test_searchFilesWithoutPattern_filePatternParameterIsRemoved_breakingChange_issue34() async throws {
        // file_pattern="*.md" を渡しても無視され、include_patterns 未指定なら既定挙動（.swift のみ）が適用される
        let response = try await runSearchFilesWithoutPattern(arguments: [
            ParameterKeys.pattern: .string("hello"),
            "file_pattern": .string("*.md"),
        ])

        // エラー応答ではない（未知パラメータ無視方針）
        XCTAssertFalse(
            response.hasPrefix("[Error]"),
            "file_pattern 指定で InvalidParams は返さない（未知パラメータとして無視）"
        )

        // .md は対象に含まれてはならない（旧 file_pattern が効くと .md が走査されてしまう）
        // 既定挙動: .swift のみ走査され、Sample.swift / SampleClass.swift（hello を含まない）が返る
        let lines = response.components(separatedBy: "\n").filter { !$0.isEmpty }
        let resultLines = lines.filter { $0.contains("/") }
        XCTAssertFalse(
            resultLines.contains(where: { $0.contains(".md") }),
            "file_pattern 廃止後は .md ファイルが対象に含まれてはならない"
        )
        // Sample.swift / SampleClass.swift は hello を含まないため結果に含まれる
        XCTAssertTrue(
            resultLines.contains(where: { $0.hasSuffix("Sample.swift") }),
            "既定挙動で hello を含まない Sample.swift が結果に含まれる"
        )
    }

    /// include_patterns で対象を絞り込める（複数 glob OR）
    func test_searchFilesWithoutPattern_includePatternsArrayRestrictsScope() async throws {
        let response = try await runSearchFilesWithoutPattern(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.includePatterns: .array([.string("*Sample*")]),
        ])

        XCTAssertFalse(response.hasPrefix("[Error]"), "正常系で [Error] にならない")

        // include_patterns=*Sample* で Sample.swift / SampleClass.swift のみ走査され
        // 両者とも hello を含まないため、両方が結果に含まれる
        let lines = response.components(separatedBy: "\n").filter { $0.contains("/") }
        XCTAssertTrue(
            lines.contains(where: { $0.hasSuffix("Sample.swift") }),
            "Sample.swift（hello 非含有）が結果に含まれる"
        )
        XCTAssertTrue(
            lines.contains(where: { $0.hasSuffix("SampleClass.swift") }),
            "SampleClass.swift（hello 非含有）が結果に含まれる"
        )
        // Foo.swift / Bar.swift は include_patterns でそもそも走査対象外
        XCTAssertFalse(
            lines.contains(where: { $0.hasSuffix("Foo.swift") }),
            "include_patterns=*Sample* なら Foo.swift は走査対象外"
        )
    }

    /// exclude_patterns は include_patterns より優先される
    func test_searchFilesWithoutPattern_excludePatternsOverridesInclude() async throws {
        let response = try await runSearchFilesWithoutPattern(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.includePatterns: .array([.string("*.swift")]),
            ParameterKeys.excludePatterns: .array([.string("*SampleClass*")]),
        ])

        XCTAssertFalse(response.hasPrefix("[Error]"), "正常系で [Error] にならない")

        let lines = response.components(separatedBy: "\n").filter { $0.contains("/") }
        // SampleClass.swift は exclude で除外され結果に含まれない
        XCTAssertFalse(
            lines.contains(where: { $0.hasSuffix("SampleClass.swift") }),
            "exclude_patterns=*SampleClass* で除外されたファイルは結果に含まれない"
        )
        // Sample.swift（hello 非含有・除外対象外）は結果に含まれる
        XCTAssertTrue(
            lines.contains(where: { $0.hasSuffix("Sample.swift") }),
            "exclude に該当しない Sample.swift は結果に残る"
        )
    }

    /// include_patterns / exclude_patterns の配列要素 20 件超過は InvalidParams エラーを返す
    func test_searchFilesWithoutPattern_arrayCountExceededReturnsError() async throws {
        let manyPatterns: [Value] = (0..<21).map { _ in .string("*.swift") }
        let response = try await runSearchFilesWithoutPattern(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.includePatterns: .array(manyPatterns),
        ])

        XCTAssertTrue(
            response.contains("配列要素数が上限を超えています") || response.contains("[Error]"),
            "include_patterns 21 件超で配列上限エラー応答（cause / suggestion 形式）"
        )
    }

    /// 不正な正規表現は構文エラー応答を返す（Tool 層の事前検証）
    func test_searchFilesWithoutPattern_invalidRegexReturnsError() async throws {
        // 未閉じグループの不正な正規表現
        let response = try await runSearchFilesWithoutPattern(arguments: [
            ParameterKeys.pattern: .string("("),
        ])

        XCTAssertTrue(
            response.contains("正規表現の構文が不正です") || response.contains("[Error]"),
            "不正な正規表現で正規表現構文エラー応答（cause / suggestion 形式）"
        )
    }

    // MARK: - キャッシュマイグレーションテスト（DES-104 §4.6 v2.0 簡素化）

    /// cacheVersion 3→最新（5） マイグレーション時に旧 v3 キャッシュは全破棄され空状態で再構築される（DES-104 §4.6）
    ///
    /// DES-104 §4.6:
    ///   旧バージョン（最新未満）キャッシュは起動時に **自動破棄・空再構築**（既存の再初期化ロジックを利用）
    ///   notes を含む全フィールドを破棄する（バージョン移行時の部分復旧は行わない）
    ///
    /// テストフロー:
    ///   1. ProjectMemory 初回生成（最新版で初期化される）→ memoryDir を特定するため
    ///   2. memory.json を v3 形式（SymbolInfo が 3 フィールド、cacheVersion=3）で上書き
    ///   3. ProjectMemory を再生成 → マイグレーションが発火し空再構築されることを検証
    func test_cacheVersion3_to_latest_migration_purgesAllEntries() async throws {
        // 1) ProjectMemory が memoryDir に memory.json を生成済み（setUp で生成）
        //    memoryDir のパスを ProjectMemory と同一のハッシュ計算で再現する
        let memoryFileURL = try locateMemoryFile(for: tempProjectDir.path, clientId: clientId)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: memoryFileURL.path),
            "ProjectMemory 初回生成で memory.json が作成されている"
        )

        // 2) v3 形式の memory.json を直接書き出す（cacheVersion=3、旧 SymbolInfo は 3 フィールド）
        //    DES-104 §4.6 旧スキーマ: name / kind / line のみ。parentScope / extensionTarget / moduleName は存在しない
        //    fileSymbolCache / importCache / typeConformanceCache に何らかの値を入れて
        //    マイグレーション時に「全破棄」されることを観察する
        let v3JSON = """
        {
          "cacheVersion": 3,
          "classDefinitions": ["LegacyClass"],
          "fileIndex": {
            "/legacy/file.swift": {
              "path": "/legacy/file.swift",
              "lastModified": -978307200
            }
          },
          "fileSymbolCache": {
            "/legacy/file.swift": [
              {
                "name": "LegacySymbol",
                "kind": "Class",
                "line": 10
              }
            ]
          },
          "importCache": {
            "/legacy/file.swift": [
              {
                "module": "Foundation",
                "line": 1
              }
            ]
          },
          "lastAnalyzed": -978307200,
          "notes": [
            {
              "timestamp": -978307200,
              "content": "legacy note (must be purged)",
              "tags": ["legacy"]
            }
          ],
          "typeConformanceCache": {
            "LegacyType": {
              "typeName": "LegacyType",
              "typeKind": "class",
              "filePath": "/legacy/file.swift",
              "line": 10,
              "protocols": ["LegacyProtocol"]
            }
          }
        }
        """
        try v3JSON.write(to: memoryFileURL, atomically: true, encoding: .utf8)

        // 3) ProjectMemory を再生成 → マイグレーション発火（v3 → v4 で全破棄・空再構築）
        let migrated = try ProjectMemory(projectPath: tempProjectDir.path)

        // 検証 (a): すべてのキャッシュが空になっている
        let allCachedSymbols = await migrated.getAllCachedSymbols()
        XCTAssertTrue(
            allCachedSymbols.isEmpty,
            "v3→最新 マイグレーションで fileSymbolCache は全破棄される（DES-104 §4.6）"
        )
        let allImports = await migrated.getAllImports()
        XCTAssertTrue(
            allImports.isEmpty,
            "v3→最新 マイグレーションで importCache は全破棄される"
        )
        let allTypeConformances = await migrated.getAllTypeConformances()
        XCTAssertTrue(
            allTypeConformances.isEmpty,
            "v3→最新 マイグレーションで typeConformanceCache は全破棄される"
        )
        let classDefinitions = await migrated.getClassDefinitions()
        XCTAssertTrue(
            classDefinitions.isEmpty,
            "v3→最新 マイグレーションで classDefinitions は全破棄される"
        )

        // 検証 (b): notes も部分復旧されず破棄される（DES-104 §4.6: notes を含む全フィールドを破棄）
        let legacyNoteHits = await migrated.searchNotes(query: "legacy")
        XCTAssertTrue(
            legacyNoteHits.isEmpty,
            "v3 の notes は最新版へ部分復旧されない（DES-104 §4.6 全破棄方針）"
        )

        // 検証 (c): cacheWarning は立たない（破損ではなくバージョン不一致のため、§4.6 ロジックは正常パス）
        let warning = await migrated.isCacheWarning()
        XCTAssertFalse(
            warning,
            "v3→最新 のバージョン不一致は破損ではないため cacheWarning は立たない"
        )

        // 検証 (d): 永続化された memory.json が最新版（v5）で再書き込みされている
        let reloadedData = try Data(contentsOf: memoryFileURL)
        let reloadedRoot = try JSONSerialization.jsonObject(with: reloadedData) as? [String: Any]
        XCTAssertEqual(
            reloadedRoot?["cacheVersion"] as? Int,
            5,
            "再保存された memory.json は最新の cacheVersion=5 に更新される"
        )
    }

    /// cacheVersion 4→5 マイグレーション時に「3 フィールド時代の SymbolInfo を保持する v4 キャッシュ」も全破棄される
    ///
    /// 背景:
    ///   v4 期間中に SymbolInfo へ parentScope / extensionTarget / moduleName を追加したため、
    ///   3 フィールド時代に書かれた v4 キャッシュが残ると新フィールドが nil で読み出される潜在不具合があった。
    ///   v5 への bump により、このような旧 v4 キャッシュも明示的に破棄され再構築されることを保証する。
    ///
    /// テストフロー:
    ///   1. ProjectMemory 初回生成（v5 で初期化される）→ memoryDir を特定するため
    ///   2. memory.json を v4 形式（SymbolInfo が 3 フィールドのみ、cacheVersion=4）で上書き
    ///   3. ProjectMemory を再生成 → v4→v5 マイグレーションが発火し空再構築されることを検証
    func test_cacheVersion4_to_5_migration_purgesLegacyV4Cache() async throws {
        // 1) memory.json の位置を特定
        let memoryFileURL = try locateMemoryFile(for: tempProjectDir.path, clientId: clientId)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: memoryFileURL.path),
            "ProjectMemory 初回生成で memory.json が作成されている"
        )

        // 2) v4 形式（旧フィールド欠落）の memory.json を直接書き出す
        //    SymbolInfo は 3 フィールド（name / kind / line）のみ。
        //    v5 では新フィールド3つを含む 6 フィールドが期待されるため、このキャッシュは破棄されるべき。
        let v4LegacyJSON = """
        {
          "cacheVersion": 4,
          "classDefinitions": ["LegacyV4Class"],
          "fileIndex": {
            "/legacy/v4.swift": {
              "path": "/legacy/v4.swift",
              "lastModified": -978307200
            }
          },
          "fileSymbolCache": {
            "/legacy/v4.swift": [
              {
                "name": "LegacyV4Symbol",
                "kind": "Class",
                "line": 10
              }
            ]
          },
          "importCache": {},
          "lastAnalyzed": -978307200,
          "notes": [],
          "typeConformanceCache": {}
        }
        """
        try v4LegacyJSON.write(to: memoryFileURL, atomically: true, encoding: .utf8)

        // 3) ProjectMemory を再生成 → v4→v5 マイグレーション発火
        let migrated = try ProjectMemory(projectPath: tempProjectDir.path)

        // 検証 (a): fileSymbolCache が全破棄されている（parentScope 欠落キャッシュは残らない）
        let allCachedSymbols = await migrated.getAllCachedSymbols()
        XCTAssertTrue(
            allCachedSymbols.isEmpty,
            "v4→v5 マイグレーションで旧フィールド欠落の fileSymbolCache は全破棄される"
        )

        // 検証 (b): classDefinitions も全破棄されている
        let classDefinitions = await migrated.getClassDefinitions()
        XCTAssertTrue(
            classDefinitions.isEmpty,
            "v4→v5 マイグレーションで classDefinitions も全破棄される"
        )

        // 検証 (c): cacheWarning は立たない（破損ではなくバージョン不一致のため）
        let warning = await migrated.isCacheWarning()
        XCTAssertFalse(
            warning,
            "v4→v5 のバージョン不一致は破損ではないため cacheWarning は立たない"
        )

        // 検証 (d): memory.json が v5 で再書き込みされている
        let reloadedData = try Data(contentsOf: memoryFileURL)
        let reloadedRoot = try JSONSerialization.jsonObject(with: reloadedData) as? [String: Any]
        XCTAssertEqual(
            reloadedRoot?["cacheVersion"] as? Int,
            5,
            "再保存された memory.json は cacheVersion=5 に更新される"
        )
    }

    // MARK: - memoryDir 解決ヘルパー（ProjectMemory.hashProjectPath と同一仕様）

    /// `ProjectMemory.init` が組み立てる memory.json の絶対パスを再現する。
    /// ProjectMemory の private な hashProjectPath と同じ計算式（SHA256 先頭 8 文字）を踏襲。
    private func locateMemoryFile(for projectPath: String, clientId: String) throws -> URL {
        let projectName = URL(fileURLWithPath: projectPath).lastPathComponent
        let hash = sha256ProjectPathPrefix(projectPath)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let memoryDir = homeDir
            .appendingPathComponent(AppConstants.storageDirectory)
            .appendingPathComponent("clients")
            .appendingPathComponent(clientId)
            .appendingPathComponent("projects")
            .appendingPathComponent("\(projectName)-\(hash)")
        return memoryDir.appendingPathComponent("memory.json")
    }

    /// `ProjectMemory.hashProjectPath` と同等のハッシュ計算（SHA256 hex 表現の先頭 8 文字）。
    private func sha256ProjectPathPrefix(_ path: String) -> String {
        let data = Data(path.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
    }
}
