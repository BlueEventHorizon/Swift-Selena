//
//  ThinkAboutAnalysisTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// 思考促進ツール
///
/// ## 目的
/// Claudeに分析の進捗を確認させ、段階的な思考を促す
///
/// ## 効果
/// - 分析の質が向上（闇雲に調査せず、整理しながら進める）
/// - 不要な深掘りを防ぐ
/// - ユーザーへの報告前に確認できる
/// - 分析結果の構造化を促進
///
/// ## 使用タイミング
/// - 複数のツールを実行した後
/// - 分析結果をまとめる前
/// - 次の調査方針を決める前
///
/// ## 使用例
/// // 複数ツール実行後
/// find_files, list_symbols, analyze_imports...
/// think_about_analysis()  ← ここで一旦整理
/// → 次のステップを決定
///
/// ## 参考
/// Serenaのthink_about_*ツール群を参考に実装
enum ThinkAboutAnalysisTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.thinkAboutAnalysis,
            description: "Reflect on collected information and plan next analysis steps",
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
        let prompt = """
        🤔 分析の進捗を確認してください：

        1. これまでに収集した情報は十分ですか？
        2. さらに調査すべき箇所はありますか？
        3. 次のステップは何ですか？
        4. ユーザーに報告できる段階ですか？

        💡 推奨：分析結果をまとめる前に、このツールで思考を整理しましょう。
        """

        return CallTool.Result(content: [.text(prompt)])
    }
}
