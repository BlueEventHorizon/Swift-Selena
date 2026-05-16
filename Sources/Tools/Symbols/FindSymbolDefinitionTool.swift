//
//  FindSymbolDefinitionTool.swift
//  Swift-Selena
//
//  Created by k2moons on 2025/10/13.
//
//  [Code Header Format]
//
//  目的
//  - プロジェクト全体から指定シンボルの定義箇所を検索し、所属スコープ情報を付与して返す
//  - DES-104 §6 に従い symbol_kinds 種別フィルタと優先返却ソートを Tool 層で完結させる
//  - SymbolInfoV2 と Memory.SymbolInfo (v4) のインライン変換とキャッシュ連携を担う
//
//  主要機能
//  - symbol_name と symbol_kinds の取得・検証（未定義値は InvalidParams を統一エラー応答化）
//  - listSymbolsWithScope によるスコープ情報付き解析とパース失敗時の skipped_files 蓄積（§8.4）
//  - 種別未指定時の priorityGroup による安定ソート（§6.2）
//  - cache_warning と skipped_files 集約済みの ResultEncoder.encodeSymbolDefinition への委譲
//
//  含まれる型
//  - SymbolDefinitionResult: encodeSymbolDefinition への入力（DES-104 §7.1）
//  - FindSymbolDefinitionTool: find_symbol_definition の MCP ツール本体
//
//  関連型
//  - SwiftSyntaxAnalyzer.SymbolInfoV2, ProjectMemory.Memory.SymbolInfo
//

import Foundation
import MCP
import Logging

/// `find_symbol_definition` の構造化出力に載せる 1 件分（DES-104 §7.1）
///
/// `FindSymbolDefinitionTool` 内で `SymbolInfoV2` / `Memory.SymbolInfo` から
/// インライン変換して組み立てる（DES-104 §4.7 配置方針）。
struct SymbolDefinitionResult: Sendable {
    let symbolName: String
    let kind: String
    let file: String
    let line: Int
    let parentScope: String?
    let extensionTarget: String?
    let moduleName: String?
}

/// シンボル定義検索ツール（DES-104 §6 拡張）
///
/// ## 目的
/// プロジェクト全体から、特定のシンボル（クラス、構造体、関数等）の定義箇所を検索し、
/// 同名シンボルを所属スコープ情報（parent / extension / module）で区別可能にする。
///
/// ## 後方互換（DES-104 §9.2）
/// - `symbol_kinds` 未指定時は全 9 区分を返し、優先返却順（Class/Struct/Enum/Protocol/Actor → 残り）でソート
/// - 出力テキストの `[Kind] Name` / `File:` / `Line:` は維持し、`Scope:` 行のみ追加
enum FindSymbolDefinitionTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.findSymbolDefinition,
            description:
                "Find where a symbol is defined in the project. Supports symbol_kinds filter (struct/class/enum/protocol/actor/function/variable/typealias/extension) and reports scope information (parent / extension target / module name).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    ParameterKeys.symbolName: .object([
                        "type": .string("string"),
                        "description": .string("Symbol name to find (class, struct, function, etc.)")
                    ]),
                    ParameterKeys.symbolKinds: .object([
                        "type": .string("array"),
                        "description": .string(
                            "Optional symbol kind filter (OR). Accepts lower-snake values: struct, class, enum, protocol, actor, function, variable, typealias, extension. Empty/omitted returns all 9 kinds. Max 9 entries."
                        ),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string(ParameterKeys.symbolName)])
            ])
        )
    }

    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result {
        let memory = try ToolHelpers.requireProjectMemory(projectMemory)

        // 1) symbol_name の取得（必須）
        let symbolName = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.symbolName,
            errorMessage: ErrorMessages.missingSymbolName
        )
        // 空文字列は無効入力として統一エラー応答（REQ-005 §4.7.2）
        guard !symbolName.isEmpty else {
            return CallTool.Result(content: [
                .text(ResultEncoder.buildErrorResponse(
                    cause: "symbol_name が空です。",
                    suggestion: "1 文字以上のシンボル名を指定してください。"
                ))
            ])
        }

        // 2) symbol_kinds の取得・検証（DES-104 §6.1 / §6.2）
        let userInputKinds: [String]
        do {
            userInputKinds = try ToolHelpers.getStringArray(
                from: params.arguments,
                key: ParameterKeys.symbolKinds,
                maxCount: 9
            )
        } catch let MCPError.invalidParams(message) {
            return CallTool.Result(content: [
                .text(symbolKindsParameterErrorResponse(message))
            ])
        }

        // 未定義の利用者指定値が含まれる場合は InvalidParams（部分的無視は行わない／REQ-005 §4.4.1）
        do {
            try SymbolKindMapper.validate(userInputKinds)
        } catch let MCPError.invalidParams(message) {
            return CallTool.Result(content: [
                .text(ResultEncoder.buildErrorResponse(
                    cause: ErrorMessages.symbolKindUndefinedCause,
                    suggestion: message ?? ErrorMessages.symbolKindUndefinedSuggestion
                ))
            ])
        } catch {
            // SymbolKindMapper.validate は InvalidParams のみスローする想定
            throw error
        }

        // 表示用 kind の許容集合に変換（空集合の場合は全 9 区分許容として扱う）
        let allowedDisplayKinds: Set<String> = Set(
            userInputKinds.compactMap { SymbolKindMapper.userInputToDisplayKind($0) }
        )
        let isKindFilterSpecified = !allowedDisplayKinds.isEmpty

        // 3) 解析対象 Swift ファイルを列挙
        let swiftFiles = try FileSearcher.findFiles(in: memory.projectPath, pattern: "*.swift")

        // 4) ファイル単位で SymbolInfoV2 を取得（キャッシュ優先、失敗時は skipped に記録）
        var foundSymbols: [SymbolDefinitionResult] = []
        var skippedFilePaths: [String] = []
        let skipLimit = ResponseLimits.maxSkippedFilesInResponse
        var totalSkippedCount = 0

        for file in swiftFiles {
            let symbolsV2: [SwiftSyntaxAnalyzer.SymbolInfoV2]
            if let cached = await memory.getCachedFileSymbols(filePath: file) {
                // キャッシュヒット: Memory.SymbolInfo (v4) → SymbolInfoV2 へインライン変換（DES-104 §6.4）
                symbolsV2 = cached.map { entry in
                    SwiftSyntaxAnalyzer.SymbolInfoV2(
                        name: entry.name,
                        kind: entry.kind,
                        line: entry.line,
                        parentScope: entry.parentScope,
                        extensionTarget: entry.extensionTarget,
                        moduleName: entry.moduleName
                    )
                }
            } else {
                // キャッシュミス: listSymbolsWithScope で解析しキャッシュ保存
                do {
                    let analyzed = try SwiftSyntaxAnalyzer.listSymbolsWithScope(filePath: file)
                    symbolsV2 = analyzed
                    // SymbolInfoV2 → Memory.SymbolInfo へインライン変換しキャッシュ保存
                    let cacheData = analyzed.map { sym in
                        ProjectMemory.Memory.SymbolInfo(
                            name: sym.name,
                            kind: sym.kind,
                            line: sym.line,
                            parentScope: sym.parentScope,
                            extensionTarget: sym.extensionTarget,
                            moduleName: sym.moduleName
                        )
                    }
                    await memory.cacheFileSymbols(filePath: file, symbols: cacheData)
                } catch {
                    // DES-104 §8.4: パース失敗ファイルは skipped_files に記録してループ継続
                    totalSkippedCount += 1
                    if skippedFilePaths.count < skipLimit {
                        skippedFilePaths.append(file)
                    }
                    logger.warning("シンボル解析に失敗（スキップ）: \(file) error=\(error)")
                    continue
                }
            }

            // 名前一致 + 種別フィルタ（指定時のみ）
            for symbol in symbolsV2 where symbol.name == symbolName {
                if isKindFilterSpecified, !allowedDisplayKinds.contains(symbol.kind) {
                    continue
                }
                foundSymbols.append(
                    SymbolDefinitionResult(
                        symbolName: symbol.name,
                        kind: symbol.kind,
                        file: file,
                        line: symbol.line,
                        parentScope: symbol.parentScope,
                        extensionTarget: symbol.extensionTarget,
                        moduleName: symbol.moduleName
                    )
                )
            }
        }

        // キャッシュ保存（失敗しても検索結果は返す）
        do {
            try await memory.save()
        } catch {
            logger.warning("シンボルキャッシュの保存に失敗: \(error)")
        }

        // 5) 種別未指定時は priorityGroup で安定ソート（DES-104 §6.2）
        if !isKindFilterSpecified {
            // Swift の sorted(by:) は安定でないため、enumerated() を用いて元順序を保つ
            foundSymbols = foundSymbols.enumerated()
                .sorted { lhs, rhs in
                    let lp = SymbolKindMapper.priorityGroup(lhs.element.kind)
                    let rp = SymbolKindMapper.priorityGroup(rhs.element.kind)
                    if lp != rp { return lp < rp }
                    return lhs.offset < rhs.offset
                }
                .map(\.element)
        }

        // 6) 0 件時は構造化結果なしの簡易応答（既存挙動を維持）
        if foundSymbols.isEmpty {
            return CallTool.Result(content: [
                .text("Symbol '\(symbolName)' not found in project")
            ])
        }

        // 7) cache_warning と skipped_files を集約して ResultEncoder に委譲
        let cacheWarning = await memory.isCacheWarning()
        let skippedTruncated = totalSkippedCount > skipLimit

        let encoded = ResultEncoder.encodeSymbolDefinition(
            symbols: foundSymbols,
            cacheWarning: cacheWarning,
            skippedFiles: skippedFilePaths,
            skippedFilesTruncated: skippedTruncated,
            totalSkippedCount: totalSkippedCount
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

    /// `getStringArray` の MCPError を DES-104 統一エラー形式へ寄せる（symbol_kinds 用）
    private static func symbolKindsParameterErrorResponse(_ message: String?) -> String {
        if let message, message.contains("exceeds maximum element count") {
            return ResultEncoder.buildErrorResponse(
                cause: ErrorMessages.arrayCountExceededCause,
                suggestion: ErrorMessages.arrayCountExceededSuggestion
            )
        }
        return ResultEncoder.buildErrorResponse(
            cause: ErrorMessages.symbolKindUndefinedCause,
            suggestion: message ?? ErrorMessages.symbolKindUndefinedSuggestion
        )
    }
}
