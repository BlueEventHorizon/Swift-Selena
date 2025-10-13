import MCP
import Foundation
import Logging
import SwiftSyntax
import SwiftParser

@main
struct SwiftMCPServer {
    static func main() async throws {
        // ロギング設定
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = .info
            return handler
        }

        let logger = Logger(label: AppConstants.loggerLabel)
        logger.info("Starting Swift MCP Server (Filesystem + SwiftSyntax)...")

        let server = Server(
            name: AppConstants.name,
            version: AppConstants.version,
            capabilities: .init(
                tools: .init()
            )
        )

        var projectMemory: ProjectMemory?

        // ツールリスト
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                // v0.5.0: 新しい構造のツール
                InitializeProjectTool.toolDefinition,
                FindFilesTool.toolDefinition,
                SearchCodeTool.toolDefinition,
                ListSymbolsTool.toolDefinition,
                FindSymbolDefinitionTool.toolDefinition,
                AddNoteTool.toolDefinition,
                SearchNotesTool.toolDefinition,
                GetProjectStatsTool.toolDefinition,
                ReadFunctionBodyTool.toolDefinition,
                ReadLinesTool.toolDefinition,
                ListPropertyWrappersTool.toolDefinition,
                ListProtocolConformancesTool.toolDefinition,
                ListExtensionsTool.toolDefinition,
                AnalyzeImportsTool.toolDefinition,
                GetTypeHierarchyTool.toolDefinition,
                FindTestCasesTool.toolDefinition,
                FindTypeUsagesTool.toolDefinition,
                // v0.5.0 新規ツール
                SetAnalysisModeTool.toolDefinition,
                ReadSymbolTool.toolDefinition,
                ListDirectoryTool.toolDefinition,
                ReadFileTool.toolDefinition,
                // v0.5.0 新規ツール
                ThinkAboutAnalysisTool.toolDefinition
            ])
        }

        // ツール実行
        await server.withMethodHandler(CallTool.self) { params in
            logger.info("Tool called: \(params.name)")

            switch params.name {
            case ToolNames.initializeProject:
                guard let args = params.arguments,
                      let projectPathValue = args[ParameterKeys.projectPath] else {
                    throw MCPError.invalidParams(ErrorMessages.missingProjectPath)
                }
                let projectPath = String(describing: projectPathValue)

                // プロジェクトパスの存在確認
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: projectPath, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    throw MCPError.invalidParams("Project path does not exist or is not a directory")
                }

                projectMemory = try ProjectMemory(projectPath: projectPath)

                return CallTool.Result(content: [
                    .text("✅ Project initialized: \(projectPath)\n\n\(projectMemory?.getStats() ?? "")")
                ])

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

            case ToolNames.listSymbols:
                return try await ListSymbolsTool.execute(
                    params: params,
                    projectMemory: projectMemory,
                    logger: logger
                )

            case ToolNames.findSymbolDefinition:
                return try await FindSymbolDefinitionTool.execute(
                    params: params,
                    projectMemory: projectMemory,
                    logger: logger
                )

            case ToolNames.addNote:
                return try await AddNoteTool.execute(
                    params: params,
                    projectMemory: projectMemory,
                    logger: logger
                )

            case ToolNames.searchNotes:
                return try await SearchNotesTool.execute(
                    params: params,
                    projectMemory: projectMemory,
                    logger: logger
                )

            case ToolNames.getProjectStats:
                return try await GetProjectStatsTool.execute(
                    params: params,
                    projectMemory: projectMemory,
                    logger: logger
                )

            case ToolNames.readFunctionBody:
                return try await ReadFunctionBodyTool.execute(
                    params: params,
                    projectMemory: projectMemory,
                    logger: logger
                )

            case ToolNames.readLines:
                return try await ReadLinesTool.execute(
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
                return try await GetTypeHierarchyTool.execute(
                    params: params,
                    projectMemory: projectMemory,
                    logger: logger
                )

            case ToolNames.findTestCases:
                return try await FindTestCasesTool.execute(
                    params: params,
                    projectMemory: projectMemory,
                    logger: logger
                )

            case ToolNames.findTypeUsages:
                return try await FindTypeUsagesTool.execute(
                    params: params,
                    projectMemory: projectMemory,
                    logger: logger
                )

            // v0.5.0 新規ツール実装

            case ToolNames.thinkAboutAnalysis:
                return try await ThinkAboutAnalysisTool.execute(
                    params: params,
                    projectMemory: projectMemory,
                    logger: logger
                )

            case ToolNames.setAnalysisMode:
                return try await SetAnalysisModeTool.execute(
                    params: params,
                    projectMemory: projectMemory,
                    logger: logger
                )

            case ToolNames.readSymbol:
                return try await ReadSymbolTool.execute(
                    params: params,
                    projectMemory: projectMemory,
                    logger: logger
                )

            case ToolNames.listDirectory:
                return try await ListDirectoryTool.execute(
                    params: params,
                    projectMemory: projectMemory,
                    logger: logger
                )

            case ToolNames.readFile:
                return try await ReadFileTool.execute(
                    params: params,
                    projectMemory: projectMemory,
                    logger: logger
                )

            default:
                throw MCPError.invalidParams("Unknown tool: \(params.name)")
            }
        }

        // Stdio transport起動
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)

        // サーバーを永続的に実行
        while true {
            try await Task.sleep(nanoseconds: 1_000_000_000_000)
        }
    }
}

