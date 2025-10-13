//
//  FindFilesTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// ファイル検索ツール
///
/// ## 目的
/// ワイルドカードパターンを使用してファイルを検索
///
/// ## 効果
/// - ファイル名パターンマッチング（`*Controller.swift`、`User*`など）
/// - プロジェクト全体から該当ファイルを高速検索
/// - ファイルの存在確認と一覧取得
///
/// ## 処理内容
/// - ワイルドカードパターンを正規表現に変換
/// - プロジェクトディレクトリを再帰的に走査
/// - パターンに一致するファイルのフルパスを収集
/// - .git、.buildなどの不要なディレクトリは自動スキップ
///
/// ## 使用シーン
/// - 特定の命名規則に従うファイルを探す時
/// - ViewControllerやModelなどの一覧取得
/// - ファイル構造の把握
/// - リファクタリング対象ファイルの洗い出し
///
/// ## 使用例
/// find_files(pattern: "*Controller.swift")
/// → Found 25 files matching '*Controller.swift':
///   /path/to/UserViewController.swift
///   /path/to/SettingsViewController.swift
///   /path/to/HomeViewController.swift
///
///
/// ## パフォーマンス（全ファイル処理する場合）
/// - 340ファイルのプロジェクトで約0.5-1秒
/// - ファイルシステム走査のみなので高速
enum FindFilesTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.findFiles,
            description: "Find Swift files in the project by pattern (glob-like search)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    ParameterKeys.pattern: .object([
                        "type": .string("string"),
                        "description": .string("File name pattern (e.g., '*Controller.swift', 'User*')")
                    ])
                ]),
                "required": .array([.string(ParameterKeys.pattern)])
            ])
        )
    }

    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result {
        let memory = try ToolHelpers.requireProjectMemory(projectMemory)
        let pattern = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.pattern,
            errorMessage: ErrorMessages.missingPattern
        )

        let files = try FileSearcher.findFiles(in: memory.projectPath, pattern: pattern)

        let result = """
        Found \(files.count) files matching '\(pattern)':

        \(files.map { "  \($0)" }.joined(separator: "\n"))
        """

        return CallTool.Result(content: [.text(result)])
    }
}
