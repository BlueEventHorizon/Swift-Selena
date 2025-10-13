//
//  GetProjectStatsTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// プロジェクト統計ツール
///
/// ## 目的
/// プロジェクトのメモリキャッシュ状態と統計情報を表示
///
/// ## 効果
/// - インデックス済みファイル数の確認
/// - キャッシュされたシンボル数の確認
/// - 保存されたノート数の確認
/// - プロジェクトパスの確認
/// - キャッシュの有効性を判断
///
/// ## 処理内容
/// - ProjectMemoryの統計情報を取得
/// - ファイルインデックス数をカウント
/// - シンボルキャッシュ数をカウント
/// - ノート数をカウント
/// - フォーマットされた統計レポートを生成
///
/// ## 使用シーン
/// - キャッシュが正しく動作しているか確認したい時
/// - プロジェクトの規模を把握したい時
/// - 初期化が完了しているか確認したい時
/// - パフォーマンス問題のデバッグ時
///
/// ## 使用例
/// get_project_stats()
/// → Project Statistics:
///   Path: /path/to/project
///   Indexed files: 340
///   Cached symbols: 1,250
///   Notes: 8
///
///
/// ## 他のツールとの連携
/// - initialize_project: 初期化後に統計を確認
/// - add_note: ノート追加後に数を確認
enum GetProjectStatsTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.getProjectStats,
            description: "Get project statistics and memory information",
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

        return CallTool.Result(content: [
            .text(memory.getStats())
        ])
    }
}
