//
//  SearchNotesTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// ノート検索ツール
///
/// ## 目的
/// 保存されたノートから関連する情報を検索
///
/// ## 効果
/// - 過去の観察や発見を素早く参照
/// - タグによる絞り込み検索
/// - タイムスタンプ付きで時系列把握
/// - プロジェクトのナレッジベースとして機能
///
/// ## 処理内容
/// - ProjectMemoryのnotesを検索
/// - クエリ文字列がコンテンツまたはタグに含まれるものを抽出
/// - 部分一致検索（大文字小文字区別なし）
/// - タイムスタンプでソート
///
/// ## 使用シーン
/// - 以前メモした情報を思い出したい時
/// - 特定のトピックに関するノートを探す時
/// - プロジェクトの設計判断を振り返る時
/// - タグで分類したノートを一覧表示
///
/// ## 使用例
/// search_notes(query: "architecture")
/// → Found 3 notes:
///   [2025-10-13 15:30] UserManagerはシングルトンパターンを使用
///     Tags: architecture, design-pattern
///   [2025-10-12 10:15] MVVMアーキテクチャを採用
///     Tags: architecture
///
///
/// ## 他のツールとの連携
/// - add_note: ノートを追加してから検索
enum SearchNotesTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.searchNotes,
            description: "Search through saved notes",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("Search query")
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        )
    }

    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result {
        let memory = try ToolHelpers.requireProjectMemory(projectMemory)
        let query = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.query,
            errorMessage: ErrorMessages.missingQuery
        )

        let notes = memory.searchNotes(query: query)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        var result = "Found \(notes.count) notes:\n\n"
        for note in notes {
            result += "[\(formatter.string(from: note.timestamp))] \(note.content)\n"
            if !note.tags.isEmpty {
                result += "  Tags: \(note.tags.joined(separator: ", "))\n"
            }
            result += "\n"
        }

        return CallTool.Result(content: [.text(result)])
    }
}
