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
//  - シンボル定義検索結果のテキスト整形（Scope 行付与）と JSON スキーマ組み立て（DES-104 §6.5）
//  - skipped_files（DES-104 §8.4）と cache_warning の JSON 反映
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

    /// `find_symbol_definition` のテキストと構造化 JSON を生成する（DES-104 §6.5・§6.6）
    ///
    /// - Parameters:
    ///   - symbols: 表示順に整列済みのシンボル一覧（Tool 層で priorityGroup ソート済み）
    ///   - cacheWarning: ProjectMemory.isCacheWarning() の結果
    ///   - skippedFiles: パース失敗ファイルのパス一覧（上限適用後）。DES-104 §8.4
    ///   - skippedFilesTruncated: skippedFiles が上限超過で切り詰められた場合 true
    ///   - totalSkippedCount: 上限適用前の総スキップ件数
    /// - Returns: テキスト本文と JSON（生成失敗時は text 末尾に `[structured output unavailable]`、json は空）
    static func encodeSymbolDefinition(
        symbols: [SymbolDefinitionResult],
        cacheWarning: Bool,
        skippedFiles: [String] = [],
        skippedFilesTruncated: Bool = false,
        totalSkippedCount: Int = 0
    ) -> (text: String, json: String) {
        let textBody = buildSymbolDefinitionText(symbols: symbols)

        do {
            let jsonString = try encodeSymbolDefinitionJSON(
                symbols: symbols,
                cacheWarning: cacheWarning,
                skippedFiles: skippedFiles,
                skippedFilesTruncated: skippedFilesTruncated,
                totalSkippedCount: totalSkippedCount
            )
            return (textBody, jsonString)
        } catch {
            let fallbackText = textBody + "\n[structured output unavailable]"
            return (fallbackText, "")
        }
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

    // MARK: - find_symbol_definition テキスト

    /// 1 シンボルあたりのスコープ行を組み立てる（DES-104 §6.5）
    ///
    /// - ルート定義（parent/extension 共に nil）: `Scope: (root)`
    /// - ネスト型: `Scope: parent=Foo`
    /// - extension 内定義: `Scope: extension=Foo`
    /// - 親と extension が同時に存在する場合（extension 内のネスト等）: `Scope: parent=A, extension=B`
    /// - moduleName が取得できた場合: ` (module=X)` を末尾に追加
    private static func buildScopeLine(_ symbol: SymbolDefinitionResult) -> String {
        var components: [String] = []
        if let parent = symbol.parentScope {
            components.append("parent=\(parent)")
        }
        if let ext = symbol.extensionTarget {
            components.append("extension=\(ext)")
        }
        let core = components.isEmpty ? "(root)" : components.joined(separator: ", ")
        if let module = symbol.moduleName {
            return "  Scope: \(core) (module=\(module))"
        }
        return "  Scope: \(core)"
    }

    /// シンボル定義検索結果のテキスト本文を組み立てる（DES-104 §6.5・§9.2）
    private static func buildSymbolDefinitionText(symbols: [SymbolDefinitionResult]) -> String {
        guard let first = symbols.first else {
            // 0 件時は呼び出し側で別ルートになる想定だが、念のため対応
            return "Found 0 definition(s)."
        }

        var lines: [String] = []
        lines.append("Found \(symbols.count) definition(s) for '\(first.symbolName)':")
        lines.append("")
        for symbol in symbols {
            lines.append("[\(symbol.kind)] \(symbol.symbolName)")
            lines.append("  File: \(symbol.file)")
            lines.append("  Line: \(symbol.line)")
            lines.append(buildScopeLine(symbol))
            lines.append("")
        }
        // 末尾の空行を除去（末尾改行は buildFinalResponse 側で付与）
        if lines.last == "" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - find_symbol_definition JSON

    private static func encodeSymbolDefinitionJSON(
        symbols: [SymbolDefinitionResult],
        cacheWarning: Bool,
        skippedFiles: [String],
        skippedFilesTruncated: Bool,
        totalSkippedCount: Int
    ) throws -> String {
        let symbolObjects: [[String: Any]] = symbols.map { sym in
            // 必須キーのみで初期化し、Optional フィールドは map で NSNull/値を一意に確定（DES-104 §7.1）
            var obj: [String: Any] = [
                "name": sym.symbolName,
                "kind": sym.kind,
                "file": sym.file,
                "line": sym.line,
            ]
            obj["parent_scope"] = sym.parentScope.map { $0 as Any } ?? NSNull()
            obj["extension_target"] = sym.extensionTarget.map { $0 as Any } ?? NSNull()
            obj["module_name"] = sym.moduleName.map { $0 as Any } ?? NSNull()
            return obj
        }

        var root: [String: Any] = [
            "total_count": symbols.count,
            "cache_warning": cacheWarning,
            "symbols": symbolObjects,
        ]

        // skipped_files が空でも DES-104 §8.4 の挙動を観察可能にするため、
        // パース失敗が発生した場合（totalSkippedCount > 0）のみ JSON ルートに含める
        if totalSkippedCount > 0 {
            root["skipped_files"] = skippedFiles
            root["skipped_files_truncated"] = skippedFilesTruncated
            root["total_skipped_count"] = totalSkippedCount
        }

        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw JSONEncodeFailure.invalidUTF8
        }
        return string
    }
}
