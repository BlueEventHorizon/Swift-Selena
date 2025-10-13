//
//  AnalyzeImportsTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// Import依存関係解析ツール
///
/// ## 目的
/// プロジェクト全体のImport文を解析し、モジュール間の依存関係を可視化
///
/// ## 効果
/// - 最も使用されているモジュールのランキングを表示
/// - 各ファイルが依存するモジュールの一覧を取得
/// - モジュールの使用頻度を定量的に把握
///
/// ## 処理内容
/// - プロジェクト内の全Swiftファイルを走査
/// - SwiftSyntaxでImport文を抽出
/// - モジュール名と行番号を記録
/// - キャッシュを利用して2回目以降は高速化
///
/// ## 使用シーン
/// - 外部依存関係の調査時
/// - 不要なモジュールの洗い出し
/// - プロジェクトのリファクタリング計画時
/// - モジュールの使用頻度分析
///
/// ## 使用例
/// analyze_imports()
/// → Most used modules:
///   Foundation: 85 files
///   SwiftUI: 42 files
///   UIKit: 28 files
///
///
/// ## パフォーマンス（全ファイル処理する場合）
/// - 340ファイルのプロジェクトで初回約3-5秒
/// - 2回目以降はキャッシュにより約0.5秒
enum AnalyzeImportsTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.analyzeImports,
            description: "Analyze import dependencies across the project",
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

        let fileImports = try SwiftSyntaxAnalyzer.analyzeImports(projectPath: memory.projectPath, projectMemory: memory)

        if fileImports.isEmpty {
            return CallTool.Result(content: [.text("No imports found in project")])
        }

        var result = "Import Dependencies Analysis:\n\n"

        // モジュールごとに集計
        var moduleUsage: [String: Int] = [:]
        for (_, imports) in fileImports {
            for imp in imports {
                moduleUsage[imp.module, default: 0] += 1
            }
        }

        result += "Most used modules:\n"
        for (module, count) in moduleUsage.sorted(by: { $0.value > $1.value }).prefix(10) {
            result += "  \(module): \(count) files\n"
        }
        result += "\n"

        result += "Files and their imports (\(fileImports.count) files):\n\n"
        for (file, imports) in fileImports.sorted(by: { $0.key < $1.key }).prefix(20) {
            let fileName = (file as NSString).lastPathComponent
            result += "\(fileName):\n"
            for imp in imports {
                result += "  └─ \(imp.module) (line \(imp.line))\n"
            }
            result += "\n"
        }

        if fileImports.count > 20 {
            result += "... and \(fileImports.count - 20) more files\n"
        }

        return CallTool.Result(content: [.text(result)])
    }
}
