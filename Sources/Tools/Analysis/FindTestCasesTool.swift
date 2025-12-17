//
//  FindTestCasesTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// テストケース検出ツール
///
/// ## 目的
/// プロジェクト内のXCTestとSwift Testingの両方のテストを自動検出
///
/// ## 効果
/// - XCTestCaseを継承するテストクラスを全て発見
/// - Swift Testing (@Test, @Suite) のテストを全て発見
/// - 各テストに含まれるテストメソッドを列挙
/// - テストカバレッジの調査を支援
///
/// ## 処理内容
/// - プロジェクト内の全Swiftファイルを走査
/// - SwiftSyntaxでXCTestCase継承クラスを検出
/// - SwiftSyntaxで@Testアトリビュートを検出
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
/// → Test Cases Summary:
///   XCTest: 2 classes, 3 methods
///   Swift Testing: 5 suites, 25 methods
///
///   === XCTest Cases (2 classes) ===
///   [TestClass] AppUITests
///     File: AppUITests.swift:10
///     Test methods (2):
///       └─ testExample (line 15)
///
///   === Swift Testing (@Test) (5 suites) ===
///   [Struct] StreamManagerTests
///     File: StreamManagerTests.swift:13
///     @Test methods (8):
///       └─ broadcastToMultipleSubscribers (line 17)
///
/// ## パフォーマンス（全ファイル処理する場合）
/// - 340ファイルのプロジェクトで約2-3秒
/// - テストファイルが少ない場合はより高速
enum FindTestCasesTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.findTestCases,
            description: "Find test cases (XCTest and Swift Testing @Test) in the project",
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

        // XCTestとSwift Testingの両方を検出
        let xcTestCases = try SwiftSyntaxAnalyzer.findTestCases(projectPath: memory.projectPath)
        let swiftTests = try SwiftSyntaxAnalyzer.findSwiftTests(projectPath: memory.projectPath)

        if xcTestCases.isEmpty && swiftTests.isEmpty {
            return CallTool.Result(content: [.text("No test cases found in project")])
        }

        // サマリー
        let xcTestMethodCount = xcTestCases.reduce(0) { $0 + $1.testMethods.count }
        let swiftTestMethodCount = swiftTests.reduce(0) { $0 + $1.testMethods.count }

        var result = "Test Cases Summary:\n"
        if !xcTestCases.isEmpty {
            result += "  XCTest: \(xcTestCases.count) classes, \(xcTestMethodCount) methods\n"
        }
        if !swiftTests.isEmpty {
            result += "  Swift Testing: \(swiftTests.count) suites, \(swiftTestMethodCount) methods\n"
        }
        result += "\n"

        // XCTest結果
        if !xcTestCases.isEmpty {
            result += "=== XCTest Cases (\(xcTestCases.count) classes) ===\n\n"

            for testClass in xcTestCases {
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
        }

        // Swift Testing結果
        if !swiftTests.isEmpty {
            result += "=== Swift Testing (@Test) (\(swiftTests.count) suites) ===\n\n"

            for suite in swiftTests {
                let fileName = (suite.filePath as NSString).lastPathComponent
                let suiteLabel = suite.hasSuiteAttribute ? "@Suite" : ""
                result += "[\(suite.suiteKind)] \(suite.suiteName)"
                if suite.suiteDisplayName != suite.suiteName {
                    result += " \"\(suite.suiteDisplayName)\""
                }
                if !suiteLabel.isEmpty {
                    result += " \(suiteLabel)"
                }
                result += "\n"
                result += "  File: \(fileName):\(suite.line)\n"

                if !suite.testMethods.isEmpty {
                    result += "  @Test methods (\(suite.testMethods.count)):\n"
                    for method in suite.testMethods {
                        if method.displayName != method.name {
                            result += "    └─ \(method.name) \"\(method.displayName)\" (line \(method.line))\n"
                        } else {
                            result += "    └─ \(method.name) (line \(method.line))\n"
                        }
                    }
                } else {
                    result += "  No @Test methods found\n"
                }
                result += "\n"
            }
        }

        return CallTool.Result(content: [.text(result)])
    }
}
