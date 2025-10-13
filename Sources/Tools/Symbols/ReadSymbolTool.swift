//
//  ReadSymbolTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// シンボル読み取りツール（コンテキスト効率）
enum ReadSymbolTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.readSymbol,
            description: "Read a specific symbol without loading entire file (context-efficient)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    ParameterKeys.filePath: .object([
                        "type": .string("string"),
                        "description": .string("Path to Swift file")
                    ]),
                    ParameterKeys.symbolPath: .object([
                        "type": .string("string"),
                        "description": .string("Symbol path (e.g., 'ClassName' or 'ClassName/methodName')")
                    ])
                ]),
                "required": .array([.string(ParameterKeys.filePath), .string(ParameterKeys.symbolPath)])
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
        let symbolPath = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.symbolPath,
            errorMessage: ErrorMessages.missingSymbolPath
        )

        // シンボル一覧を取得
        let symbols = try SwiftSyntaxAnalyzer.listSymbols(filePath: filePath)

        // symbolPathでシンボルを検索（単純なマッチング）
        let matchingSymbol = symbols.first { $0.name == symbolPath }

        guard let symbol = matchingSymbol else {
            throw MCPError.invalidRequest(ErrorMessages.symbolNotFound + ": '\(symbolPath)' in \(filePath)")
        }

        // シンボルの開始行から関数本体を読み取る
        let content = try String(contentsOfFile: filePath)
        let lines = content.components(separatedBy: .newlines)

        // シンボルの行から開始
        let startIndex = max(0, symbol.line - 1)
        var symbolLines: [String] = []
        var braceCount = 0
        var started = false

        for i in startIndex..<lines.count {
            let line = lines[i]
            symbolLines.append(line)

            if line.contains("{") {
                started = true
            }

            if started {
                braceCount += line.filter { $0 == "{" }.count
                braceCount -= line.filter { $0 == "}" }.count

                if braceCount == 0 {
                    break
                }
            }
        }

        let result = """
        [\(symbol.kind)] \(symbol.name)
        Location: \(filePath):\(symbol.line)

        ```swift
        \(symbolLines.joined(separator: "\n"))
        ```
        """

        return CallTool.Result(content: [.text(result)])
    }
}
