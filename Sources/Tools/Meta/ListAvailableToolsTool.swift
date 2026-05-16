//
//  ListAvailableToolsTool.swift
//  Swift-Selena
//
//  Created on 2025/12/14.
//
//  [Code Header Format]
//
//  目的
//  - 利用可能ツール一覧を簡易形式で返す（メタツール）
//  - トークン消費削減のため詳細な JSON Schema は返さない
//  - REQ-005 §4.7.1 ケーパビリティ通知に対応（CapabilityRegistry 経由）
//
//  主要機能
//  - CapabilityRegistry.availableTools() で現環境で利用可能なツール名を取得
//  - MetaToolRegistry でカテゴリ別に整形して返却
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

        // DES-104 §7.2 / TASK-013: CapabilityRegistry 経由で動作可能ツールを取得
        // 本 Feature では全ツールが無条件で利用可能なため、整形結果は従来と同等。
        // 将来、前提条件を持つツールが追加された際は availableToolNames で絞り込まれる。
        let availableToolNames = Set(CapabilityRegistry.availableTools())
        let result = MetaToolRegistry.formatToolList(filter: availableToolNames)
        return CallTool.Result(content: [.text(result)])
    }
}
