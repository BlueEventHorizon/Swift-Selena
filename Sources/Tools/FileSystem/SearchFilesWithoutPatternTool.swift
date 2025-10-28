//
//  SearchFilesWithoutPatternTool.swift
//  Swift-Selena
//
//  Created on 2025/10/27.
//

import Foundation
import MCP
import Logging

/// パターンにマッチしないファイルを検索するツール（grep -L相当）
///
/// ## 目的
/// 正規表現パターンにマッチ**しない**ファイルを検索
///
/// ## 効果
/// - Code Header未作成ファイルの一括検出
/// - Import未記述ファイルの発見
/// - ドキュメント整備状況の確認
/// - 品質チェック・コンプライアンス確認
///
/// ## 処理内容
/// - プロジェクト内の全ファイルを走査（オプションでfilePatternで絞り込み）
/// - 各ファイルの全内容を読み込み
/// - 正規表現パターンにマッチ**しない**ファイルを収集
/// - ファイルパス、統計情報（チェック数、該当数、割合）を返却
/// - .git、.buildなどの不要なディレクトリは自動スキップ
///
/// ## 使用シーン
/// - Code Headerフォーマットが未適用のファイルを探す時
/// - Import文が欠けているファイルを洗い出す時
/// - ドキュメント整備の進捗確認
/// - 特定のマーカーやアノテーションの適用漏れチェック
///
/// ## 使用例
/// search_files_without_pattern(pattern: "\\[Code Header Format\\]")
/// → Found 163 files without pattern:
///   UserManager.swift
///   AuthService.swift
///
///   Files checked: 263
///   Files without pattern: 163 (61.9%)
///
///
/// ## search_codeとの違い
/// - search_code: パターンに**マッチする**行を返す
/// - search_files_without_pattern: パターンに**マッチしない**ファイルを返す（grep -L相当）
///
/// ## パフォーマンス（全ファイル処理する場合）
/// - 263ファイルのプロジェクトで約1-2秒
/// - 各ファイル全体を読み込むため、search_codeより若干遅い
enum SearchFilesWithoutPatternTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.searchFilesWithoutPattern,
            description: "Find files that do NOT match the given pattern (like grep -L)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    ParameterKeys.pattern: .object([
                        "type": .string("string"),
                        "description": .string("Regex pattern to search for (files WITHOUT this pattern will be returned)")
                    ]),
                    ParameterKeys.filePattern: .object([
                        "type": .string("string"),
                        "description": .string("Optional file pattern to limit search (e.g., '*.swift')")
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
        let filePattern = params.arguments?[ParameterKeys.filePattern].map { String(describing: $0) }

        let filesWithoutPattern = try FileSearcher.searchFilesWithoutPattern(
            in: memory.projectPath,
            pattern: pattern,
            filePattern: filePattern
        )

        // 統計情報のため、全ファイル数を取得
        let allFiles = try FileSearcher.findFiles(
            in: memory.projectPath,
            pattern: filePattern ?? "*.swift"
        )
        let totalFiles = allFiles.count
        let filesWithoutCount = filesWithoutPattern.count
        let percentage = totalFiles > 0 ? Double(filesWithoutCount) / Double(totalFiles) * 100.0 : 0.0

        var result = "Found \(filesWithoutCount) files without pattern '\(pattern)':\n\n"
        for file in filesWithoutPattern {
            result += "  \(file)\n"
        }

        result += "\nFiles checked: \(totalFiles)\n"
        result += "Files without pattern: \(filesWithoutCount) (\(String(format: "%.1f%%", percentage)))\n"

        return CallTool.Result(content: [.text(result)])
    }
}
