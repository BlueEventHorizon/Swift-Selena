//
//  GetToolSchemaTool.swift
//  Swift-Selena
//
//  Created on 2025/12/14.
//
//  Purpose: Anthropicの「コード実行パターン」適用
//  - 特定ツールの完全なJSON Schemaを返す
//  - 必要な時に必要なツールの定義だけを取得
//

import Foundation
import MCP
import Logging

/// 特定ツールのJSON Schemaを返すメタツール
///
/// ## 目的
/// 指定されたツールの完全なJSON Schema（inputSchema）を返す
///
/// ## 効果
/// - 必要なツールの定義のみを動的にロード
/// - execute_tool呼び出し前にパラメータを確認可能
///
/// ## 使用例
/// get_tool_schema(tool_name: "find_files")
/// → {
///     "name": "find_files",
///     "description": "Find Swift files in the project by pattern",
///     "inputSchema": { ... }
///   }
enum GetToolSchemaTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: MetaToolNames.getToolSchema,
            description: "Get the full JSON schema for a specific tool",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    MetaParameterKeys.toolName: .object([
                        "type": .string("string"),
                        "description": .string("Name of the tool to get schema for (e.g., 'find_files', 'list_symbols')")
                    ])
                ]),
                "required": .array([.string(MetaParameterKeys.toolName)])
            ])
        )
    }

    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result {
        let toolName = try ToolHelpers.getString(
            from: params.arguments,
            key: MetaParameterKeys.toolName,
            errorMessage: "Missing tool_name parameter"
        )

        logger.info("get_tool_schema called for: \(toolName)")

        guard let tool = MetaToolRegistry.getToolDefinition(toolName) else {
            // ツールが見つからない場合、利用可能なツール名を提示
            let availableTools = MetaToolRegistry.allToolNames.joined(separator: ", ")
            throw MCPError.invalidParams(
                "Unknown tool: '\(toolName)'. Available tools: \(availableTools)"
            )
        }

        // Tool定義をJSON形式で出力
        let result = formatToolSchema(tool)
        return CallTool.Result(content: [.text(result)])
    }

    /// Tool定義を人間が読みやすい形式でフォーマット
    private static func formatToolSchema(_ tool: Tool) -> String {
        var result = "Tool Schema for '\(tool.name)':\n\n"
        result += "Name: \(tool.name)\n"
        result += "Description: \(tool.description ?? "No description")\n\n"
        result += "Input Schema:\n"
        result += formatValue(tool.inputSchema, indent: 2)

        return result
    }

    /// MCP Value型を文字列にフォーマット
    private static func formatValue(_ value: Value, indent: Int) -> String {
        let indentStr = String(repeating: " ", count: indent)

        switch value {
        case .string(let str):
            return "\"\(str)\""
        case .int(let num):
            return "\(num)"
        case .double(let num):
            return "\(num)"
        case .bool(let val):
            return val ? "true" : "false"
        case .null:
            return "null"
        case .array(let arr):
            if arr.isEmpty {
                return "[]"
            }
            let items = arr.map { formatValue($0, indent: indent + 2) }.joined(separator: ", ")
            return "[\(items)]"
        case .object(let dict):
            if dict.isEmpty {
                return "{}"
            }
            var lines: [String] = ["{"]
            for (key, val) in dict.sorted(by: { $0.key < $1.key }) {
                let formattedVal = formatValue(val, indent: indent + 2)
                lines.append("\(indentStr)  \"\(key)\": \(formattedVal)")
            }
            lines.append("\(indentStr)}")
            return lines.joined(separator: "\n")
        case .data(let mimeType, let bytes):
            let mimeInfo = mimeType ?? "unknown"
            return "<data: \(bytes.count) bytes, type: \(mimeInfo)>"
        }
    }
}
