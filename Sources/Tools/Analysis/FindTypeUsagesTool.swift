//
//  FindTypeUsagesTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// 型使用箇所検出ツール
///
/// ## 目的
/// 指定した型がプロジェクト内のどこで使用されているかを検出
///
/// ## 効果
/// - 変数宣言での型使用を検出（`let user: User`）
/// - 関数パラメータでの型使用を検出（`func save(user: User)`）
/// - 関数戻り値での型使用を検出（`func getUser() -> User`）
/// - リファクタリング影響範囲の特定を支援
///
/// ## 処理内容
/// - プロジェクト内の全Swiftファイルを走査
/// - SwiftSyntaxで型注釈を解析
/// - 指定された型名に一致する使用箇所を抽出
/// - 使用コンテキスト（変数/パラメータ/戻り値）を分類
///
/// ## 使用シーン
/// - 型の依存関係を調査したい時
/// - 型名変更の影響範囲を確認したい時
/// - 型の使用頻度を調べたい時
/// - リファクタリング前の影響調査
///
/// ## 使用例
/// find_type_usages(type_name: "User")
/// → Type Usages for 'User' (15 usages):
///   [Variable] let user: User
///     File: ViewController.swift:42
///   [Parameter] func updateUser(user: User)
///     File: UserManager.swift:18
///   [ReturnType] func getCurrentUser() -> User
///     File: AuthService.swift:55
///
///
/// ## パフォーマンス（全ファイル処理する場合）
/// - 340ファイルのプロジェクトで約3-4秒
/// - 型使用が多い場合は結果が大量になる可能性あり
enum FindTypeUsagesTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.findTypeUsages,
            description: "Find where a specific type is used in the project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "type_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the type to find usages for")
                    ])
                ]),
                "required": .array([.string("type_name")])
            ])
        )
    }

    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result {
        let memory = try ToolHelpers.requireProjectMemory(projectMemory)
        let typeName = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.typeName,
            errorMessage: ErrorMessages.missingTypeName
        )

        let usages = try SwiftSyntaxAnalyzer.findTypeUsages(typeName: typeName, projectPath: memory.projectPath)

        if usages.isEmpty {
            return CallTool.Result(content: [.text("No usages found for type '\(typeName)'")])
        }

        var result = "Type Usages for '\(typeName)' (\(usages.count) usages):\n\n"

        for usage in usages {
            let fileName = (usage.filePath as NSString).lastPathComponent
            result += "[\(usage.usageKind)] \(usage.context)\n"
            result += "  File: \(fileName):\(usage.line)\n\n"
        }

        return CallTool.Result(content: [.text(result)])
    }
}
