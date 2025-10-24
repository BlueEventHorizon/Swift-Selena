//
//  FindSymbolReferencesTool.swift
//  Swift-Selena
//
//  Created on 2025/10/21.
//

import Foundation
import MCP
import Logging

/// シンボル参照検索ツール（LSP版）
///
/// ## 目的
/// 型情報ベースの正確な参照検索（ビルド可能時のみ利用可能）
///
/// ## 効果
/// - メソッド呼び出し箇所の正確な検出
/// - プロパティアクセスの検出
/// - 型推論による正確な参照
/// - find_type_usagesより高精度
///
/// ## 使用条件
/// - ビルド可能なプロジェクト（LSP接続成功時のみ）
/// - ビルド不可の場合はエラー
///
/// ## 使用シーン
/// - リファクタリング時の影響範囲確認
/// - 未使用コードの検出
/// - メソッド呼び出し箇所の把握
///
/// ## 使用例
/// ```
/// find_symbol_references(
///   file_path: "UserManager.swift",
///   line: 15,
///   column: 10
/// )
/// → Found 8 references:
///   ViewController.swift:42
///   LoginService.swift:28
///   ...
/// ```
///
/// ## find_type_usagesとの違い
/// - find_type_usages: 型名ベース（SwiftSyntax、ビルド不要）
/// - find_symbol_references: 位置ベース（LSP、ビルド必要、高精度）
enum FindSymbolReferencesTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.findSymbolReferences,
            description: "Find all references to a symbol at given position (LSP: requires buildable project)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    ParameterKeys.filePath: .object([
                        "type": .string("string"),
                        "description": .string("File path")
                    ]),
                    ParameterKeys.line: .object([
                        "type": .string("integer"),
                        "description": .string("Line number (1-indexed)")
                    ]),
                    ParameterKeys.column: .object([
                        "type": .string("integer"),
                        "description": .string("Column number (1-indexed)")
                    ])
                ]),
                "required": .array([
                    .string(ParameterKeys.filePath),
                    .string(ParameterKeys.line),
                    .string(ParameterKeys.column)
                ])
            ])
        )
    }

    // MCPToolプロトコル準拠用（使用されない）
    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result {
        throw MCPError.invalidRequest("This tool requires LSP state. Use execute(params:projectMemory:lspState:logger:) instead.")
    }

    // LSPState付きの実際の実装
    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        lspState: LSPState,
        logger: Logger
    ) async throws -> CallTool.Result {
        // LSP利用可能性チェックは呼び出し側で実施済み

        let filePath = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.filePath,
            errorMessage: ErrorMessages.missingFilePath
        )
        let line = ToolHelpers.getInt(from: params.arguments, key: ParameterKeys.line, defaultValue: 1)
        let column = ToolHelpers.getInt(from: params.arguments, key: ParameterKeys.column, defaultValue: 1)

        // LSPClient取得
        guard let lspClient = await lspState.getClient() else {
            throw MCPError.invalidRequest("""
                ❌ LSP not available.

                This tool requires a buildable project with SourceKit-LSP.

                💡 Alternatives:
                - Use 'find_type_usages' for type-level reference search (SwiftSyntax)
                - Use 'search_code' for text-based search
                """)
        }

        // LSP参照検索（0-indexed）
        let locations: [LSPLocation]
        do {
            locations = try await lspClient.findReferences(
                filePath: filePath,
                line: line - 1,  // 1-indexed → 0-indexed
                column: column - 1
            )
        } catch {
            logger.error("LSP findReferences failed: \(error)")
            throw MCPError.internalError("LSP request failed: \(error.localizedDescription)")
        }

        // 結果フォーマット
        guard !locations.isEmpty else {
            return CallTool.Result(content: [
                .text("No references found for symbol at \(filePath):\(line):\(column)")
            ])
        }

        var result = "Found \(locations.count) reference(s):\n\n"
        for loc in locations {
            result += "  \(loc.filePath):\(loc.line)\n"
        }

        return CallTool.Result(content: [.text(result)])
    }
}
