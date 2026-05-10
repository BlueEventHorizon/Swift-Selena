//
//  ResultEncoder.swift
//  Swift-Selena
//
//  Created by k2moons on 2026/05/10.
//
//  [Code Header Format]
//
//  目的
//  - search_code / find_symbol_definition のテキスト出力と構造化 JSON の生成
//  - MCP 応答末尾への structured ブロック結合と入力検証エラーの統一整形（DES-104 §7.1・§8.1）
//  - JSON 生成失敗時はテキストのみとし利用者へ明示する（DES-104 §8.3）
//
//  主要機能
//  - コード検索結果のモード別テキスト整形と JSON スキーマ組み立て（マッチ行は前後空白除去）
//  - 最終応答文字列への structured セクション付与
//  - ツール共通のエラー表示形式の生成
//
//  関連型
//  - SearchCodeResult, SearchOutputMode, Match（FileSearcher）
//  - SymbolDefinitionResult（FindSymbolDefinitionTool）
//

import Foundation

/// 検索・シンボルツールの結果を MCP 向け文字列に整形する（状態を持たない）
enum ResultEncoder {

    // MARK: - Public API

    /// `search_code` のテキストと構造化 JSON を生成する（DES-104 §7.1・§5.2）
    static func encodeSearchCode(
        result: SearchCodeResult,
        mode: SearchOutputMode,
        cacheWarning: Bool
    ) -> (text: String, json: String) {
        let textBody = buildSearchCodeText(result: result, mode: mode)

        do {
            let jsonString = try encodeSearchCodeJSON(result: result, mode: mode, cacheWarning: cacheWarning)
            return (textBody, jsonString)
        } catch {
            let fallbackText = textBody + "\n[structured output unavailable]"
            return (fallbackText, "")
        }
    }

    /// `find_symbol_definition` 用（TASK-012 で本体実装）
    static func encodeSymbolDefinition(
        symbols: [SymbolDefinitionResult],
        cacheWarning: Bool
    ) -> (text: String, json: String) {
        fatalError("encodeSymbolDefinition is not yet implemented — will be completed in TASK-012")
    }

    /// テキスト本文と JSON を MCP 応答用に結合する（DES-104 §2 TBD-004）
    static func buildFinalResponse(_ text: String, _ json: String) -> String {
        text + "\n--- structured ---\n" + json
    }

    /// 入力検証エラーなどの統一フォーマット（DES-104 §8.1）
    static func buildErrorResponse(cause: String, suggestion: String) -> String {
        "[Error]\ncause: \(cause)\nsuggestion: \(suggestion)"
    }

    // MARK: - search_code テキスト

    private static func buildSearchCodeText(result: SearchCodeResult, mode: SearchOutputMode) -> String {
        switch mode {
        case .matchDetail:
            var lines: [String] = []
            lines.append("Found \(result.totalMatchCount) matches:")
            lines.append("")
            for m in result.matches {
                let trimmed = m.content.trimmingCharacters(in: .whitespaces)
                lines.append("\(m.file):\(m.line): \(trimmed)")
            }
            if result.truncated {
                lines.append("[Truncated: showing \(result.matches.count) of \(result.totalMatchCount) matches]")
            }
            return lines.joined(separator: "\n")

        case .fileList:
            var lines: [String] = []
            lines.append("Found \(result.totalFileCount) files:")
            lines.append("")
            lines.append(contentsOf: result.files)
            if result.truncated {
                lines.append("[Truncated: showing \(result.files.count) of \(result.totalFileCount) files]")
            }
            return lines.joined(separator: "\n")

        case .countOnly:
            return "Matches: \(result.totalMatchCount)\nFiles: \(result.totalFileCount)"
        }
    }

    // MARK: - search_code JSON

    private static func encodeSearchCodeJSON(
        result: SearchCodeResult,
        mode: SearchOutputMode,
        cacheWarning: Bool
    ) throws -> String {
        var root: [String: Any] = [
            "total_match_count": result.totalMatchCount,
            "total_file_count": result.totalFileCount,
            "truncated": result.truncated,
            "truncated_to_max_limit": result.truncatedToMaxLimit,
            "cache_warning": cacheWarning,
        ]

        switch mode {
        case .matchDetail:
            let matchObjects: [[String: Any]] = result.matches.map {
                [
                    "file": $0.file,
                    "line": $0.line,
                    "content": $0.content.trimmingCharacters(in: .whitespaces),
                ]
            }
            root["matches"] = matchObjects

        case .fileList:
            root["matches"] = [Any]()
            root["files"] = result.files

        case .countOnly:
            root["matches"] = [Any]()
            root["files"] = [Any]()
        }

        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw JSONEncodeFailure.invalidUTF8
        }
        return string
    }

    private enum JSONEncodeFailure: Error {
        case invalidUTF8
    }
}
