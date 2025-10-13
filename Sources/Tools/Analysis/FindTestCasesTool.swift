//
//  FindTestCasesTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// XCTestケース検出ツール
///
/// ## 目的
/// プロジェクト内のXCTestクラスとテストメソッドを自動検出
///
/// ## 効果
/// - XCTestCaseを継承するテストクラスを全て発見
/// - 各テストクラスに含まれるtest*メソッドを列挙
/// - テストカバレッジの調査を支援
///
/// ## 処理内容
/// - プロジェクト内の全Swiftファイルを走査
/// - SwiftSyntaxでXCTestCase継承クラスを検出
/// - `test`で始まるメソッドを抽出
/// - ファイルパスと行番号を記録
///
/// ## 使用シーン
/// - テストコードの全体像を把握したい時
/// - テストクラスの数を確認したい時
/// - テストメソッドの命名規則を調査する時
/// - テストの網羅性を検証する時
///
/// ## 使用例
/// find_test_cases()
/// → XCTest Cases (12 classes):
///   [TestClass] UserManagerTests
///     File: UserManagerTests.swift:10
///     Test methods (5):
///       └─ testCreateUser (line 15)
///       └─ testDeleteUser (line 25)
///
///
/// ## パフォーマンス（全ファイル処理する場合）
/// - 340ファイルのプロジェクトで約2-3秒
/// - テストファイルが少ない場合はより高速
enum FindTestCasesTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.findTestCases,
            description: "Find XCTest test cases and methods in the project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:])
            ])
        )
    }

    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result {
        let memory = try ToolHelpers.requireProjectMemory(projectMemory)

        let testCases = try SwiftSyntaxAnalyzer.findTestCases(projectPath: memory.projectPath)

        if testCases.isEmpty {
            return CallTool.Result(content: [.text("No XCTest cases found in project")])
        }

        var result = "XCTest Cases (\(testCases.count) classes):\n\n"

        for testClass in testCases {
            let fileName = (testClass.filePath as NSString).lastPathComponent
            result += "[TestClass] \(testClass.className)\n"
            result += "  File: \(fileName):\(testClass.line)\n"

            if !testClass.testMethods.isEmpty {
                result += "  Test methods (\(testClass.testMethods.count)):\n"
                for method in testClass.testMethods {
                    result += "    └─ \(method.name) (line \(method.line))\n"
                }
            } else {
                result += "  No test methods found\n"
            }

            result += "\n"
        }

        return CallTool.Result(content: [.text(result)])
    }
}
