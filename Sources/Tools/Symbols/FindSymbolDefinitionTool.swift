//
//  FindSymbolDefinitionTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// シンボル定義検索ツール
///
/// ## 目的
/// プロジェクト全体から、特定のシンボル（クラス、関数、構造体等）の定義箇所を検索
///
/// ## 効果
/// - シンボル名だけで定義箇所を特定
/// - ファイル名がわからなくても検索可能
/// - 複数ファイルに同名シンボルがある場合、全て検出
///
/// ## 処理内容
/// - **全Swiftファイル**をスキャン
/// - 各ファイルのシンボル一覧と照合
/// - マッチするシンボルの位置情報を返す
///
/// ## 使用シーン
/// - 「AgentManagerクラスはどこ？」
/// - 「initメソッドの定義は？」
/// - シンボル名のみで検索したい場合
///
/// ## 使用例
/// find_symbol_definition(symbol_name: "AgentManager")
/// → File: App/Agent/AgentManager.swift:7
///
/// ## list_symbols との違い
/// - list_symbols: 1ファイル内の全シンボルを列挙
/// - find_symbol_definition: 全ファイルから特定シンボルを検索
///
/// ## パフォーマンス
/// - 約1秒（340ファイル処理）
enum FindSymbolDefinitionTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.findSymbolDefinition,
            description: "Find where a symbol is defined in the project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "symbol_name": .object([
                        "type": .string("string"),
                        "description": .string("Symbol name to find (class, struct, function, etc.)")
                    ])
                ]),
                "required": .array([.string("symbol_name")])
            ])
        )
    }

    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result {
        let memory = try ToolHelpers.requireProjectMemory(projectMemory)
        let symbolName = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.symbolName,
            errorMessage: ErrorMessages.missingSymbolName
        )

        // プロジェクト内の全Swiftファイルを検索
        let swiftFiles = try FileSearcher.findFiles(in: memory.projectPath, pattern: "*.swift")
        var foundSymbols: [(file: String, symbol: SwiftSyntaxAnalyzer.SymbolInfo)] = []

        for file in swiftFiles {
            let symbols = try SwiftSyntaxAnalyzer.listSymbols(filePath: file)
            for symbol in symbols where symbol.name == symbolName {
                foundSymbols.append((file: file, symbol: symbol))
            }
        }

        if foundSymbols.isEmpty {
            return CallTool.Result(content: [.text("Symbol '\(symbolName)' not found in project")])
        }

        var result = "Found \(foundSymbols.count) definition(s) for '\(symbolName)':\n\n"
        for (file, symbol) in foundSymbols {
            result += "[\(symbol.kind)] \(symbol.name)\n"
            result += "  File: \(file)\n"
            result += "  Line: \(symbol.line)\n\n"
        }

        return CallTool.Result(content: [.text(result)])
    }
}
