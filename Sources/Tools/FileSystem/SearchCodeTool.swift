//
//  SearchCodeTool.swift
//  Swift-Selena
//
//  Created by k2moons on 2025/10/13.
//
//  [Code Header Format]
//
//  目的
//  - プロジェクト内ソースの正規表現検索（grep 相当）を MCP ツールとして提供する
//  - DES-104 に従い出力モード・件数上限・include/exclude glob を Tool 層で検証してから検索する
//  - 構造化 JSON と cache_warning を ResultEncoder 経由で応答に載せる（§7.1・§8.2）
//
//  主要機能
//  - pattern / output_mode / limit / include_patterns / exclude_patterns の取得と入力検証（§5.3）
//  - 廃止パラメータ file_pattern はスキーマから除外し、指定されても無視する（§5.1）
//  - FileSearcher の拡張 searchCode と ProjectMemory.isCacheWarning を組み合わせた応答生成
//

import Foundation
import MCP
import Logging

/// コード検索ツール（grep 風・DES-104 拡張）
enum SearchCodeTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.searchCode,
            description:
                "Search code content using regex (grep-like). Supports output_mode, limit, include_patterns, exclude_patterns (glob).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    ParameterKeys.pattern: .object([
                        "type": .string("string"),
                        "description": .string("Regex pattern to search for (required)")
                    ]),
                    ParameterKeys.outputMode: .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: match_detail (default), file_list, or count_only"
                        )
                    ]),
                    ParameterKeys.limit: .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Optional max results (1–10000). Values above 10000 are clamped with notification. Ignored when output_mode is count_only."
                        )
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
                    ]),
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

        // §5.3 入力検証フロー: pattern → limit → include/exclude（glob）

        // 1) pattern: 正規表現構文の事前検証（Tool 層責務／§4.0）
        do {
            _ = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            return CallTool.Result(content: [
                .text(ResultEncoder.buildErrorResponse(
                    cause: ErrorMessages.regexSyntaxErrorCause,
                    suggestion: ErrorMessages.regexSyntaxErrorSuggestion
                ))
            ])
        }

        // 2) limit: 0 以下はエラー、10000 超は Core がクリップ＋truncated_to_max_limit（TBD-010）
        let limitOptional: Int?
        do {
            limitOptional = try ToolHelpers.getOptionalInt(
                from: params.arguments,
                key: ParameterKeys.limit
            )
        } catch let MCPError.invalidParams(message) {
            return CallTool.Result(content: [
                .text(ResultEncoder.buildErrorResponse(
                    cause: ErrorMessages.limitBoundaryErrorCause,
                    suggestion: message ?? ErrorMessages.limitBoundaryErrorSuggestion
                ))
            ])
        }

        if let lim = limitOptional, lim <= 0 {
            return CallTool.Result(content: [
                .text(ResultEncoder.buildErrorResponse(
                    cause: ErrorMessages.limitBoundaryErrorCause,
                    suggestion: ErrorMessages.limitBoundaryErrorSuggestion
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

        // 3) include / exclude: glob 事前検証（wildcardToRegex + NSRegularExpression）
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

        let outputMode: SearchOutputMode
        switch parseOutputMode(from: params.arguments) {
        case .ok(let mode):
            outputMode = mode
        case .invalid(let cause, let suggestion):
            return CallTool.Result(content: [
                .text(ResultEncoder.buildErrorResponse(cause: cause, suggestion: suggestion))
            ])
        }

        let cacheWarning = await memory.isCacheWarning()

        let searchResult: SearchCodeResult
        do {
            searchResult = try FileSearcher.searchCode(
                in: memory.projectPath,
                pattern: pattern,
                includePatterns: includePatterns,
                excludePatterns: excludePatterns,
                limit: limitOptional,
                outputMode: outputMode
            )
        } catch {
            if let localized = error as? LocalizedError,
               let cause = localized.errorDescription,
               let suggestion = localized.recoverySuggestion {
                return CallTool.Result(content: [
                    .text(ResultEncoder.buildErrorResponse(cause: cause, suggestion: suggestion))
                ])
            }
            throw error
        }

        let encoded = ResultEncoder.encodeSearchCode(
            result: searchResult,
            mode: outputMode,
            cacheWarning: cacheWarning
        )

        let finalText: String
        if encoded.json.isEmpty {
            finalText = encoded.text
        } else {
            finalText = ResultEncoder.buildFinalResponse(encoded.text, encoded.json)
        }

        return CallTool.Result(content: [.text(finalText)])
    }

    // MARK: - 入力検証ヘルパー

    private enum ParsedOutputMode {
        case ok(SearchOutputMode)
        case invalid(cause: String, suggestion: String)
    }

    private static func parseOutputMode(from args: [String: Value]?) -> ParsedOutputMode {
        guard let args, let value = args[ParameterKeys.outputMode] else {
            return .ok(.matchDetail)
        }
        if case .null = value {
            return .ok(.matchDetail)
        }
        guard case .string(let raw) = value else {
            return .invalid(
                cause: "output_mode の型が不正です。",
                suggestion: "文字列で次のいずれかを指定してください: match_detail, file_list, count_only"
            )
        }
        switch raw {
        case "match_detail":
            return .ok(.matchDetail)
        case "file_list":
            return .ok(.fileList)
        case "count_only":
            return .ok(.countOnly)
        default:
            return .invalid(
                cause: "output_mode の値が不正です。",
                suggestion: "次のいずれかを指定してください: match_detail, file_list, count_only"
            )
        }
    }

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
