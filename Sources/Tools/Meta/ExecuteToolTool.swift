//
//  ExecuteToolTool.swift
//  Swift-Selena
//
//  Created on 2025/12/14.
//
//  Purpose: Anthropicの「コード実行パターン」適用
//  - 指定されたツールを実行する
//  - メタツールモードでの実際のツール実行を担当
//

import Foundation
import MCP
import Logging

/// ツール実行メタツール
///
/// ## 目的
/// 指定されたツール名とパラメータでツールを実行する
///
/// ## 効果
/// - メタツールモードで全ツールにアクセス可能
/// - ツール実行の一元管理
///
/// ## 使用例
/// execute_tool(tool_name: "find_files", params: { "pattern": "*Controller.swift" })
/// → Found 25 files matching '*Controller.swift':
///   /path/to/UserViewController.swift
///   ...
enum ExecuteToolTool {
    static var toolDefinition: Tool {
        Tool(
            name: MetaToolNames.executeTool,
            description: "Execute a Swift analysis tool with parameters",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    MetaParameterKeys.toolName: .object([
                        "type": .string("string"),
                        "description": .string("Name of the tool to execute (e.g., 'find_files', 'list_symbols')")
                    ]),
                    MetaParameterKeys.params: .object([
                        "type": .string("object"),
                        "description": .string("Tool parameters as JSON object (e.g., { \"pattern\": \"*.swift\" })")
                    ])
                ]),
                "required": .array([.string(MetaParameterKeys.toolName)])
            ])
        )
    }

    /// ツール実行（LSP対応版）
    /// - Parameters:
    ///   - params: CallToolパラメータ
    ///   - projectMemory: プロジェクトメモリ
    ///   - lspState: LSP状態（list_symbols, get_type_hierarchy用）
    ///   - logger: ロガー
    /// - Returns: ツール実行結果
    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        lspState: LSPState,
        logger: Logger
    ) async throws -> CallTool.Result {
        // tool_nameを抽出
        let toolName = try ToolHelpers.getString(
            from: params.arguments,
            key: MetaParameterKeys.toolName,
            errorMessage: "Missing tool_name parameter"
        )

        logger.info("execute_tool called for: \(toolName)")

        // paramsを抽出（オプション）
        var innerArgs: [String: Value]? = nil
        if let args = params.arguments,
           let paramsValue = args[MetaParameterKeys.params],
           case .object(let paramsDict) = paramsValue {
            innerArgs = paramsDict
        }

        // 内部ツール呼び出し用のパラメータを構築
        let innerParams = CallTool.Parameters(
            name: toolName,
            arguments: innerArgs
        )

        // ツールをディスパッチ
        return try await dispatchTool(
            toolName: toolName,
            params: innerParams,
            projectMemory: projectMemory,
            lspState: lspState,
            logger: logger
        )
    }

    /// ツール名に基づいて適切なツールを実行
    private static func dispatchTool(
        toolName: String,
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        lspState: LSPState,
        logger: Logger
    ) async throws -> CallTool.Result {
        switch toolName {
        // initialize_projectは直接公開されているため、ここでは対応しない
        // （execute_tool経由でも呼び出せるが、推奨しない）

        case ToolNames.findFiles:
            return try await FindFilesTool.execute(
                params: params,
                projectMemory: projectMemory,
                logger: logger
            )

        case ToolNames.searchCode:
            return try await SearchCodeTool.execute(
                params: params,
                projectMemory: projectMemory,
                logger: logger
            )

        case ToolNames.searchFilesWithoutPattern:
            return try await SearchFilesWithoutPatternTool.execute(
                params: params,
                projectMemory: projectMemory,
                logger: logger
            )

        case ToolNames.listSymbols:
            // LSP強化版
            return try await ListSymbolsTool.executeWithLSP(
                params: params,
                projectMemory: projectMemory,
                lspState: lspState,
                logger: logger
            )

        case ToolNames.findSymbolDefinition:
            return try await FindSymbolDefinitionTool.execute(
                params: params,
                projectMemory: projectMemory,
                logger: logger
            )

        case ToolNames.listPropertyWrappers:
            return try await ListPropertyWrappersTool.execute(
                params: params,
                projectMemory: projectMemory,
                logger: logger
            )

        case ToolNames.listProtocolConformances:
            return try await ListProtocolConformancesTool.execute(
                params: params,
                projectMemory: projectMemory,
                logger: logger
            )

        case ToolNames.listExtensions:
            return try await ListExtensionsTool.execute(
                params: params,
                projectMemory: projectMemory,
                logger: logger
            )

        case ToolNames.analyzeImports:
            return try await AnalyzeImportsTool.execute(
                params: params,
                projectMemory: projectMemory,
                logger: logger
            )

        case ToolNames.getTypeHierarchy:
            // LSP強化版
            return try await GetTypeHierarchyTool.executeWithLSP(
                params: params,
                projectMemory: projectMemory,
                lspState: lspState,
                logger: logger
            )

        case ToolNames.findTestCases:
            return try await FindTestCasesTool.execute(
                params: params,
                projectMemory: projectMemory,
                logger: logger
            )

        case ToolNames.initializeProject:
            // initialize_projectはexecute_tool経由では実行できない
            // （ProjectMemoryの初期化ロジックがSwiftMCPServer側にあるため）
            throw MCPError.invalidParams(
                "initialize_project cannot be called via execute_tool. Use it directly."
            )

        default:
            let availableTools = MetaToolRegistry.allToolNames.joined(separator: ", ")
            throw MCPError.invalidParams(
                "Unknown tool: '\(toolName)'. Available tools: \(availableTools)"
            )
        }
    }
}
