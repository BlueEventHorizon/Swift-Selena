//
//  ListSymbolsTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// シンボル一覧ツール
///
/// ## 目的
/// ファイル内の全てのシンボル（Class、Struct、Function等）を一覧表示
///
/// ## 効果
/// - ファイルの構造を素早く把握
/// - Class、Struct、Enum、Protocol、Function、Variableを検出
/// - 各シンボルの種類と行番号を取得
/// - ファイル全体のコードマップを作成
///
/// ## 処理内容
/// - SwiftSyntaxでファイルをパース
/// - SyntaxVisitorでASTを走査
/// - シンボルの種類を判定（Class/Struct/Enum/Protocol/Function/Variable）
/// - シンボル名と行番号を記録
/// - SourceLocationConverterで正確な行番号を取得
///
/// ## 使用シーン
/// - 初めて見るファイルの構造を理解したい時
/// - ファイルにどんな機能があるか把握したい時
/// - 特定のシンボルがどこにあるか探す時
/// - コードレビューで全体像を掴みたい時
///
/// ## 使用例
/// list_symbols(file_path: "UserManager.swift")
/// → Symbols in UserManager.swift:
///   [Class] UserManager (line 10)
///   [Function] createUser (line 15)
///   [Function] deleteUser (line 25)
///   [Struct] UserData (line 40)
///   [Enum] UserRole (line 55)
///
///
/// ## 他のツールとの違い
/// - list_symbols: ファイル内の全シンボルを列挙（高速、概要把握）
/// - find_symbol_definition: 名前でシンボルを検索（プロジェクト全体）
/// - read_symbol: 特定シンボルの詳細を読み取り
enum ListSymbolsTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.listSymbols,
            description: "List all symbols (classes, structs, functions, etc.) in a file using SwiftSyntax",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to Swift file")
                    ])
                ]),
                "required": .array([.string("file_path")])
            ])
        )
    }

    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result {
        let filePath = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.filePath,
            errorMessage: ErrorMessages.missingFilePath
        )

        let symbols = try SwiftSyntaxAnalyzer.listSymbols(filePath: filePath)

        var result = "Symbols in \(filePath):\n\n"
        for symbol in symbols {
            result += "[\(symbol.kind)] \(symbol.name) (line \(symbol.line))\n"
        }

        return CallTool.Result(content: [.text(result)])
    }

    /// LSP強化版実行（v0.5.4）
    static func executeWithLSP(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        lspState: LSPState,
        logger: Logger
    ) async throws -> CallTool.Result {
        let filePath = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.filePath,
            errorMessage: ErrorMessages.missingFilePath
        )

        // LSP利用可能性チェック
        let isLSPAvailable = await lspState.isLSPAvailable()

        if isLSPAvailable {
            logger.info("Using LSP for list_symbols (enhanced)")

            // LSP版: documentSymbol APIで型情報付き取得
            do {
                if let client = await lspState.getClient() {
                    let lspSymbols = try await client.documentSymbol(filePath: filePath)

                    if !lspSymbols.isEmpty {
                        var result = "Symbols in \(filePath) (LSP enhanced):\n\n"
                        for symbol in lspSymbols {
                            let kindName = symbolKindToString(symbol.kind)
                            if let detail = symbol.detail {
                                result += "[\(kindName)] \(symbol.name): \(detail) (line \(symbol.line))\n"
                            } else {
                                result += "[\(kindName)] \(symbol.name) (line \(symbol.line))\n"
                            }
                        }
                        return CallTool.Result(content: [.text(result)])
                    }
                }
            } catch {
                logger.warning("LSP documentSymbol failed, falling back to SwiftSyntax: \(error)")
            }
        }

        // フォールバック: SwiftSyntax版
        logger.info("Using SwiftSyntax for list_symbols")
        let symbols = try SwiftSyntaxAnalyzer.listSymbols(filePath: filePath)

        var result = "Symbols in \(filePath):\n\n"
        for symbol in symbols {
            result += "[\(symbol.kind)] \(symbol.name) (line \(symbol.line))\n"
        }

        return CallTool.Result(content: [.text(result)])
    }

    /// LSP SymbolKind を文字列に変換
    private static func symbolKindToString(_ kind: Int) -> String {
        switch kind {
        case 1: return "File"
        case 2: return "Module"
        case 3: return "Namespace"
        case 4: return "Package"
        case 5: return "Class"
        case 6: return "Method"
        case 7: return "Property"
        case 8: return "Field"
        case 9: return "Constructor"
        case 10: return "Enum"
        case 11: return "Interface"
        case 12: return "Function"
        case 13: return "Variable"
        case 14: return "Constant"
        case 22: return "EnumMember"
        case 23: return "Struct"
        default: return "Unknown(\(kind))"
        }
    }
}
