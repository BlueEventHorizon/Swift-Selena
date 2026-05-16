//
//  SearchCodeToolTests.swift
//  SwiftMCPServerTests
//
//  Created by k2moons on 2026/05/16.
//
//  [Code Header Format]
//
//  目的
//  - SearchCodeTool（DES-104 §5 / §11.1）の挙動を網羅する単体テスト
//  - output_mode / limit / include_patterns / exclude_patterns の正常系・境界値・異常系を検証
//  - 廃止された file_pattern が無視されること、include/exclude 衝突時の優先順位を回帰防止する
//
//  主要機能
//  - 一時ディレクトリに Swift fixture を配置し SearchCodeTool.execute を直接呼び出して結果を検証
//  - structured ブロック（JSON）の truncated / truncated_to_max_limit フラグ判定
//  - 不正正規表現・不正 glob・limit 範囲外・配列上限超過の InvalidParams 形式エラー応答検証
//
//  含まれる型
//  - SearchCodeToolTests: XCTestCase
//
//  関連型
//  - SearchCodeTool, FileSearcher, SearchCodeResult, ResultEncoder, ProjectMemory
//

import XCTest
import Foundation
import MCP
import Logging
@testable import Swift_Selena

final class SearchCodeToolTests: XCTestCase {

    // MARK: - テストフィクスチャ

    private var tempProjectDir: URL!
    private var clientId: String!
    private var projectMemory: ProjectMemory!
    private let logger = Logger(label: "SearchCodeToolTests")

    override func setUp() async throws {
        try await super.setUp()

        // クライアント ID を UUID で一意化（ProjectMemory のキャッシュを衝突させない）
        clientId = UUID().uuidString
        setenv("MCP_CLIENT_ID", clientId, 1)

        // 一時プロジェクトディレクトリを作成
        tempProjectDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("search_code_tool_tests_\(UUID().uuidString)")
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

        unsetenv("MCP_CLIENT_ID")
        try await super.tearDown()
    }

    // MARK: - fixture 配置ヘルパー

    /// プロジェクト直下に複数の Swift / 非 Swift ファイルを書き出す
    private func writeFixtures() throws {
        try writeFile(relativePath: "Sources/Foo.swift", content: """
        struct Foo {
            func hello() { print("hello") }
            func world() { print("world") }
        }
        """)
        try writeFile(relativePath: "Sources/Bar.swift", content: """
        struct Bar {
            func hello() { print("hello bar") }
        }
        """)
        try writeFile(relativePath: "Tests/FooTests.swift", content: """
        import XCTest
        final class FooTests: XCTestCase {
            func testHello() { print("hello test") }
        }
        """)
        try writeFile(relativePath: "README.md", content: """
        # Sample README
        hello documentation
        """)
    }

    /// 大量マッチ用に N 件 "hello" を含むファイルを書く
    private func writeManyMatchesFixture(count: Int, fileName: String = "Sources/Many.swift") throws {
        var lines: [String] = ["struct Many {"]
        for i in 0..<count {
            lines.append("    let hello_\(i) = \"hello\"")
        }
        lines.append("}")
        try writeFile(relativePath: fileName, content: lines.joined(separator: "\n"))
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

    // MARK: - 正常系: output_mode

    /// match_detail（既定）モードはファイル・行番号・マッチ行を返す
    func testOutputModeMatchDetail() async throws {
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.outputMode: .string("match_detail"),
        ])
        let parts = splitStructured(response)

        XCTAssertTrue(parts.text.hasPrefix("Found "), "match_detail は 'Found N matches:' で始まる")
        XCTAssertTrue(parts.text.contains("Foo.swift"), "Foo.swift のマッチが含まれる")
        XCTAssertTrue(parts.text.contains(":"), "ファイル:行番号: 内容 フォーマットが含まれる")

        guard let json = parts.json.flatMap(parseJSON) else {
            return XCTFail("structured JSON が取得できない")
        }
        XCTAssertNotNil(json["matches"])
        if let matches = json["matches"] as? [[String: Any]] {
            XCTAssertFalse(matches.isEmpty, "match_detail の matches が空でない")
            // 各エントリは file / line / content を持つ
            for match in matches {
                XCTAssertNotNil(match["file"])
                XCTAssertNotNil(match["line"])
                XCTAssertNotNil(match["content"])
            }
        } else {
            XCTFail("matches が配列でない")
        }
    }

    /// file_list モードはマッチを含むファイル一覧を重複排除で返す
    func testOutputModeFileList() async throws {
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.outputMode: .string("file_list"),
        ])
        let parts = splitStructured(response)

        XCTAssertTrue(parts.text.hasPrefix("Found "), "file_list は 'Found N files:' で始まる")

        guard let json = parts.json.flatMap(parseJSON) else {
            return XCTFail("structured JSON が取得できない")
        }
        guard let files = json["files"] as? [String] else {
            return XCTFail("files フィールドが配列でない")
        }
        // 重複排除されている
        XCTAssertEqual(files.count, Set(files).count, "file_list のファイルは重複排除されている")
        // すべて .swift で fixture が登場する
        XCTAssertTrue(files.contains(where: { $0.hasSuffix("Foo.swift") }))
        XCTAssertTrue(files.contains(where: { $0.hasSuffix("Bar.swift") }))
    }

    /// count_only モードはマッチ数・ファイル数のみ返す
    func testOutputModeCountOnly() async throws {
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.outputMode: .string("count_only"),
        ])
        let parts = splitStructured(response)

        XCTAssertTrue(parts.text.contains("Matches:"), "Matches: 行が含まれる")
        XCTAssertTrue(parts.text.contains("Files:"), "Files: 行が含まれる")

        guard let json = parts.json.flatMap(parseJSON) else {
            return XCTFail("structured JSON が取得できない")
        }
        // count_only は matches も files も空配列で総数のみ返す
        if let matches = json["matches"] as? [Any] {
            XCTAssertTrue(matches.isEmpty, "count_only は matches=[]")
        }
        if let files = json["files"] as? [Any] {
            XCTAssertTrue(files.isEmpty, "count_only は files=[]")
        }
        XCTAssertNotNil(json["total_match_count"])
        XCTAssertNotNil(json["total_file_count"])
    }

    // MARK: - 正常系: limit

    /// limit 指定で件数が切り詰められ truncated=true が付く
    func testLimitTruncation() async throws {
        // hello を多く含むファイルを追加
        try writeManyMatchesFixture(count: 10)

        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.limit: .int(5),
        ])
        let parts = splitStructured(response)

        guard let json = parts.json.flatMap(parseJSON) else {
            return XCTFail("structured JSON が取得できない")
        }
        // truncated フラグ
        if let truncated = json["truncated"] as? Bool {
            XCTAssertTrue(truncated, "limit=5 でマッチ 10+ なら truncated=true")
        } else {
            XCTFail("truncated フィールドが Bool でない")
        }
        // matches の件数が 5 件
        if let matches = json["matches"] as? [[String: Any]] {
            XCTAssertEqual(matches.count, 5, "切り詰め後の matches は 5 件")
        }
        // 上限適用前の総数は 5 件超
        if let total = json["total_match_count"] as? Int {
            XCTAssertGreaterThan(total, 5, "total_match_count は上限適用前の総数")
        }
    }

    // MARK: - 正常系: include / exclude

    /// include_patterns + exclude_patterns（複数指定、除外優先）
    func testIncludeAndExcludePatterns() async throws {
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.outputMode: .string("file_list"),
            ParameterKeys.includePatterns: .array([.string("*.swift")]),
            ParameterKeys.excludePatterns: .array([.string("*Tests*")]),
        ])
        let parts = splitStructured(response)

        guard let json = parts.json.flatMap(parseJSON),
              let files = json["files"] as? [String] else {
            return XCTFail("structured JSON / files が取得できない")
        }

        // Tests 配下は除外、Sources 配下は含まれる
        XCTAssertFalse(files.contains(where: { $0.contains("Tests/FooTests.swift") }),
                       "*Tests* で除外されたファイルが含まれてはならない")
        XCTAssertTrue(files.contains(where: { $0.hasSuffix("Foo.swift") }))
        XCTAssertTrue(files.contains(where: { $0.hasSuffix("Bar.swift") }))
    }

    /// 既定挙動: include / exclude を省略すると .swift のみ走査される
    func testDefaultBehaviorScansOnlySwiftFiles() async throws {
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.outputMode: .string("file_list"),
        ])
        let parts = splitStructured(response)

        guard let json = parts.json.flatMap(parseJSON),
              let files = json["files"] as? [String] else {
            return XCTFail("structured JSON / files が取得できない")
        }

        // README.md は対象外であること
        XCTAssertFalse(files.contains(where: { $0.hasSuffix(".md") }),
                       "既定挙動では .md ファイルが対象外")
        // 全結果が .swift で終わる
        for file in files {
            XCTAssertTrue(file.hasSuffix(".swift"), "既定挙動では .swift のみが対象 - 違反: \(file)")
        }
    }

    /// file_pattern が指定されても無視される（廃止パラメータ、§5.1）
    func testFilePatternIsIgnored() async throws {
        // file_pattern="*.md" を渡しても無視され、include_patterns 未指定なら .swift のみ対象
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.outputMode: .string("file_list"),
            "file_pattern": .string("*.md"),
        ])
        let parts = splitStructured(response)

        guard let json = parts.json.flatMap(parseJSON),
              let files = json["files"] as? [String] else {
            return XCTFail("structured JSON / files が取得できない")
        }
        XCTAssertFalse(files.contains(where: { $0.hasSuffix(".md") }),
                       "file_pattern は廃止済みのため .md は対象外のまま")
        XCTAssertFalse(files.isEmpty, "既定挙動で .swift がマッチするはず")
    }

    // MARK: - 境界値: limit=10000 / 10001

    /// limit=10000（境界値・ぎりぎり）→ truncated_to_max_limit=false
    func testLimitAtMaxBoundary() async throws {
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.limit: .int(10000),
        ])
        let parts = splitStructured(response)

        guard let json = parts.json.flatMap(parseJSON) else {
            return XCTFail("structured JSON が取得できない")
        }
        if let flag = json["truncated_to_max_limit"] as? Bool {
            XCTAssertFalse(flag, "limit=10000 は最大値そのものなので切り詰め通知は出ない")
        } else {
            XCTFail("truncated_to_max_limit フィールドが Bool でない")
        }
    }

    /// limit=10001（境界値・最大値超過）→ 10000 に切り詰め、truncated_to_max_limit=true
    func testLimitJustAboveMaxBoundary() async throws {
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.limit: .int(10001),
        ])
        let parts = splitStructured(response)

        guard let json = parts.json.flatMap(parseJSON) else {
            return XCTFail("structured JSON が取得できない")
        }
        if let flag = json["truncated_to_max_limit"] as? Bool {
            XCTAssertTrue(flag, "limit=10001 では truncated_to_max_limit=true")
        } else {
            XCTFail("truncated_to_max_limit フィールドが Bool でない")
        }
    }

    // MARK: - 異常系: pattern 不正

    /// 不正な正規表現は cause / suggestion 付きエラー
    func testInvalidRegexPatternReturnsError() async throws {
        // 閉じ括弧不足の不正正規表現
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("(unclosed"),
        ])

        XCTAssertTrue(response.hasPrefix("[Error]"), "エラーは [Error] で始まる")
        XCTAssertTrue(response.contains("cause:"), "cause: を含む")
        XCTAssertTrue(response.contains("suggestion:"), "suggestion: を含む")
        XCTAssertTrue(response.contains(ErrorMessages.regexSyntaxErrorCause),
                      "正規表現構文エラー文言を含む")
    }

    // MARK: - 異常系: limit 範囲外

    /// limit=0 はエラー
    func testLimitZeroReturnsError() async throws {
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.limit: .int(0),
        ])
        XCTAssertTrue(response.hasPrefix("[Error]"))
        XCTAssertTrue(response.contains(ErrorMessages.limitBoundaryErrorCause),
                      "limit 境界エラー文言を含む")
    }

    /// limit=-1 はエラー
    func testLimitNegativeReturnsError() async throws {
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.limit: .int(-1),
        ])
        XCTAssertTrue(response.hasPrefix("[Error]"))
        XCTAssertTrue(response.contains(ErrorMessages.limitBoundaryErrorCause))
    }

    /// limit=20000 は 10000 にクランプ・通知（エラーではなく成功応答 + truncated_to_max_limit）
    func testLimitClampNotification() async throws {
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.limit: .int(20000),
        ])
        let parts = splitStructured(response)

        // 成功応答であること（エラー文言で始まらない）
        XCTAssertFalse(parts.text.hasPrefix("[Error]"),
                       "10000 超でもエラーにせず通知形式")
        guard let json = parts.json.flatMap(parseJSON) else {
            return XCTFail("structured JSON が取得できない")
        }
        if let flag = json["truncated_to_max_limit"] as? Bool {
            XCTAssertTrue(flag, "limit=20000 で truncated_to_max_limit=true")
        } else {
            XCTFail("truncated_to_max_limit フィールドが Bool でない")
        }
    }

    // MARK: - 異常系: 配列要素数上限

    /// include_patterns が 21 件 → 上限超過エラー
    func testIncludePatternsExceedingMaxCountReturnsError() async throws {
        let patterns: [Value] = (0..<21).map { .string("*\($0).swift") }
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.includePatterns: .array(patterns),
        ])
        XCTAssertTrue(response.hasPrefix("[Error]"))
        XCTAssertTrue(response.contains(ErrorMessages.arrayCountExceededCause),
                      "配列要素数上限超過の cause を含む")
    }

    /// exclude_patterns が 21 件 → 上限超過エラー
    func testExcludePatternsExceedingMaxCountReturnsError() async throws {
        let patterns: [Value] = (0..<21).map { .string("*\($0).swift") }
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.excludePatterns: .array(patterns),
        ])
        XCTAssertTrue(response.hasPrefix("[Error]"))
        XCTAssertTrue(response.contains(ErrorMessages.arrayCountExceededCause))
    }

    // MARK: - 異常系: glob 構文エラー

    /// include_patterns に不正 glob → エラー（"[unclosed" 等）
    func testInvalidIncludeGlobSyntaxReturnsError() async throws {
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.includePatterns: .array([.string("[unclosed")]),
        ])
        XCTAssertTrue(response.hasPrefix("[Error]"))
        XCTAssertTrue(response.contains(ErrorMessages.globSyntaxErrorCause),
                      "include の glob 構文エラーの cause を含む")
        XCTAssertTrue(response.contains(ErrorMessages.globSyntaxErrorSuggestion),
                      "DES-104 §8.1 固定 suggestion 文言を含む")
    }

    /// exclude_patterns に不正 glob → エラー
    func testInvalidExcludeGlobSyntaxReturnsError() async throws {
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.excludePatterns: .array([.string("[unclosed")]),
        ])
        XCTAssertTrue(response.hasPrefix("[Error]"))
        XCTAssertTrue(response.contains(ErrorMessages.globSyntaxErrorCause),
                      "exclude の glob 構文エラーの cause を含む")
    }

    // MARK: - 異常系: include / exclude 衝突

    /// include と exclude が同一ファイルに合致した場合、exclude が優先（0 件）
    func testIncludeAndExcludeCollisionExcludeWins() async throws {
        let response = try await runSearchCode(arguments: [
            ParameterKeys.pattern: .string("hello"),
            ParameterKeys.outputMode: .string("file_list"),
            ParameterKeys.includePatterns: .array([.string("*.swift")]),
            ParameterKeys.excludePatterns: .array([.string("*.swift")]),
        ])
        let parts = splitStructured(response)

        guard let json = parts.json.flatMap(parseJSON) else {
            return XCTFail("structured JSON が取得できない")
        }
        // 全 .swift が除外され合致ファイル 0 件
        if let files = json["files"] as? [String] {
            XCTAssertEqual(files.count, 0, "exclude 優先で 0 件になるはず")
        } else {
            XCTFail("files フィールドが配列でない")
        }
        if let total = json["total_match_count"] as? Int {
            XCTAssertEqual(total, 0, "exclude 優先で total_match_count=0")
        }
    }
}
