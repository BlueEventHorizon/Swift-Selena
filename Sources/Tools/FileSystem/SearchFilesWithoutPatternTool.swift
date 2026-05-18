//
//  SearchFilesWithoutPatternTool.swift
//  Swift-Selena
//
//  Created by k2moons on 2025/10/27.
//
//  [Code Header Format]
//
//  目的
//  - 正規表現にマッチしないファイル一覧を MCP ツールとして提供する（grep -L 相当）
//  - DES-104 §5.1 に従い `file_pattern` を廃止し `include_patterns` / `exclude_patterns` で対象を絞り込む
//  - search_code とパラメータ仕様を揃え、Tool 層で入力検証してから FileSearcher へ委譲する
//
//  主要機能
//  - pattern / include_patterns / exclude_patterns の取得と入力検証（DES-104 §5.3）
//  - 廃止パラメータ file_pattern はスキーマから除外し、指定されても無視する（§5.1）
//  - 評価規則は search_code と共通の shouldSearchFile を再利用（include OR、exclude 優先）
//

import Foundation
import MCP
import Logging

/// パターンにマッチしないファイルを検索するツール（grep -L 相当）
///
/// ## 目的
/// 正規表現パターンにマッチ**しない**ファイルを検索
///
/// ## 効果
/// - Code Header 未作成ファイルの一括検出
/// - Import 未記述ファイルの発見
/// - ドキュメント整備状況の確認
/// - 品質チェック・コンプライアンス確認
///
/// ## 処理内容
/// - プロジェクト内の対象ファイルを走査（include_patterns / exclude_patterns で絞り込み）
/// - 各ファイルの全内容を読み込み
/// - 正規表現パターンにマッチ**しない**ファイルを収集
/// - ファイルパス、統計情報（チェック数、該当数、割合）を返却
/// - .git、.build などの不要なディレクトリは自動スキップ
///
/// ## 使用シーン
/// - Code Header フォーマットが未適用のファイルを探す時
/// - Import 文が欠けているファイルを洗い出す時
/// - ドキュメント整備の進捗確認
/// - 特定のマーカーやアノテーションの適用漏れチェック
///
/// ## 使用例
/// search_files_without_pattern(pattern: "\\[Code Header Format\\]", include_patterns: ["Sources/**/*.swift"])
/// → Found 163 files without pattern:
///   UserManager.swift
///   AuthService.swift
///
///   Files checked: 263
///   Files without pattern: 163 (61.9%)
///
/// ## search_code との違い
/// - search_code: パターンに**マッチする**行を返す
/// - search_files_without_pattern: パターンに**マッチしない**ファイルを返す（grep -L 相当）
enum SearchFilesWithoutPatternTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.searchFilesWithoutPattern,
            description: "Find files that do NOT match the given pattern (like grep -L). Supports include_patterns / exclude_patterns (glob).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    ParameterKeys.pattern: .object([
                        "type": .string("string"),
                        "description": .string("Regex pattern to search for (files WITHOUT this pattern will be returned)")
                    ]),
                    ParameterKeys.includePatterns: .object([
                        "type": .string("array"),
                        "description": .string(
                            "Optional glob patterns to include (OR). Empty means default *.swift behavior. Max 20 entries."
                        ),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ]),
                    ParameterKeys.excludePatterns: .object([
                        "type": .string("array"),
                        "description": .string(
                            "Optional glob patterns to exclude (OR; wins over include). Max 20 entries."
                        ),
                        "items": .object([
                            "type": .string("string")
                        ])
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

        // pattern: 正規表現構文の事前検証（Tool 層責務／DES-104 §4.0）
        do {
            _ = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        } catch {
            return CallTool.Result(content: [
                .text(ResultEncoder.buildErrorResponse(
                    cause: ErrorMessages.regexSyntaxErrorCause,
                    suggestion: ErrorMessages.regexSyntaxErrorSuggestion
                ))
            ])
        }

        let includePatterns: [String]
        let excludePatterns: [String]
        do {
            includePatterns = try ToolHelpers.getStringArray(
                from: params.arguments,
                key: ParameterKeys.includePatterns,
                maxCount: 20
            )
            excludePatterns = try ToolHelpers.getStringArray(
                from: params.arguments,
                key: ParameterKeys.excludePatterns,
                maxCount: 20
            )
        } catch let MCPError.invalidParams(message) {
            return CallTool.Result(content: [.text(stringArrayParameterErrorResponse(message))])
        }

        // include / exclude: glob 事前検証（wildcardToRegex + NSRegularExpression）
        do {
            try validateGlobSyntax(includePatterns)
            try validateGlobSyntax(excludePatterns)
        } catch {
            return CallTool.Result(content: [
                .text(ResultEncoder.buildErrorResponse(
                    cause: ErrorMessages.globSyntaxErrorCause,
                    suggestion: ErrorMessages.globSyntaxErrorSuggestion
                ))
            ])
        }

        let searchResult = try FileSearcher.searchFilesWithoutPattern(
            in: memory.projectPath,
            pattern: pattern,
            includePatterns: includePatterns,
            excludePatterns: excludePatterns
        )
        let filesWithoutPattern = searchResult.filesWithoutPattern
        let totalFiles = searchResult.totalChecked
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

    // MARK: - 入力検証ヘルパー

    /// include / exclude の各要素が glob→正規表現変換後もコンパイル可能か検証する
    private static func validateGlobSyntax(_ patterns: [String]) throws {
        for glob in patterns {
            let regexPattern = FileSearcher.wildcardToRegex(glob)
            _ = try NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive])
        }
    }

    /// `getStringArray` の MCPError を DES-104 の統一エラー形式へ寄せる
    private static func stringArrayParameterErrorResponse(_ message: String?) -> String {
        if let message, message.contains("exceeds maximum element count") {
            return ResultEncoder.buildErrorResponse(
                cause: ErrorMessages.arrayCountExceededCause,
                suggestion: ErrorMessages.arrayCountExceededSuggestion
            )
        }
        return ResultEncoder.buildErrorResponse(
            cause: "include_patterns または exclude_patterns が不正です。",
            suggestion: message ?? ErrorMessages.globSyntaxErrorSuggestion
        )
    }
}
