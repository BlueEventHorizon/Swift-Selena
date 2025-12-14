//
//  ListAvailableToolsTool.swift
//  Swift-Selena
//
//  Created on 2025/12/14.
//
//  Purpose: Anthropicの「コード実行パターン」適用
//  - 利用可能なツールの一覧を簡易形式で返す
//  - トークン消費を削減するため、詳細なJSON Schemaは返さない
//

import Foundation
import MCP
import Logging

/// 利用可能なツール一覧を返すメタツール
///
/// ## 目的
/// Swift-Selenaで利用可能な全ツールの名前と説明を返す
///
/// ## 効果
/// - トークン消費の大幅削減（詳細なJSON Schemaを返さない）
/// - ツール発見を容易にする
/// - カテゴリ別にグループ化された出力
///
/// ## 使用例
/// list_available_tools()
/// → Available Swift-Selena Tools (11 tools):
///   Search & Files:
///   - find_files: Find files by pattern (glob-like)
///   - search_code: Search code content (grep-like)
///   ...
enum ListAvailableToolsTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: MetaToolNames.listAvailableTools,
            description: "List all available Swift analysis tools (name and description only, no full schema)",
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
        logger.info("list_available_tools called")

        let result = MetaToolRegistry.formatToolList()
        return CallTool.Result(content: [.text(result)])
    }
}
