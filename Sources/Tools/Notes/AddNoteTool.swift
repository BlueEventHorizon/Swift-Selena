//
//  AddNoteTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// ノート追加ツール
///
/// ## 目的
/// プロジェクトに関する観察や発見をメモとして永続保存
///
/// ## 効果
/// - セッションをまたいで情報を保持
/// - タグによる分類管理
/// - タイムスタンプ自動記録
/// - 後で検索可能なナレッジベース構築
///
/// ## 処理内容
/// - ProjectMemoryのnotesに追加
/// - 現在時刻を自動記録
/// - オプションでタグを複数指定可能
/// - JSONファイルに永続化
///
/// ## 使用シーン
/// - コードの重要な発見をメモしたい時
/// - リファクタリング計画を記録したい時
/// - バグの原因や解決策を記録したい時
/// - プロジェクトの設計思想を記録したい時
///
/// ## 使用例
/// add_note(content: "UserManagerはシングルトンパターンを使用", tags: ["architecture", "design-pattern"])
/// → ✅ Note saved: UserManagerはシングルトンパターンを使用
///
///
/// ## 他のツールとの連携
/// - search_notes: 保存したノートを検索
/// - get_project_stats: ノート数を確認
enum AddNoteTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.addNote,
            description: "Add a note about the project (persisted across sessions)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("Note content")
                    ]),
                    "tags": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("string")
                        ]),
                        "description": .string("Optional tags for categorization")
                    ])
                ]),
                "required": .array([.string("content")])
            ])
        )
    }

    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result {
        let memory = try ToolHelpers.requireProjectMemory(projectMemory)
        let content = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.content,
            errorMessage: ErrorMessages.missingContent
        )

        var tags: [String] = []
        if let tagsValue = params.arguments?[ParameterKeys.tags] {
            let tagsStr = String(describing: tagsValue)
            tags = tagsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        memory.addNote(content: content, tags: tags)
        try memory.save()

        return CallTool.Result(content: [
            .text("✅ Note saved: \(content)")
        ])
    }
}
