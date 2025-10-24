import MCP
import Foundation
import Logging
import SwiftSyntax
import SwiftParser

@main
struct SwiftMCPServer {
    static func main() async throws {
        // v0.5.3: ファイルログ設定
        let logFilePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swift-selena/logs/server.log")
            .path

        // ロギング設定
        LoggingSystem.bootstrap { label in
            if let handler = try? FileLogHandler(logFilePath: logFilePath) {
                var h = handler
                h.logLevel = .info
                return h
            } else {
                // フォールバック: stderr
                var handler = StreamLogHandler.standardError(label: label)
                handler.logLevel = .info
                return handler
            }
        }

        let logger = Logger(label: AppConstants.loggerLabel)
        logger.info("Starting Swift MCP Server (Filesystem + SwiftSyntax + LSP)...")
        logger.info("Log file: \(logFilePath)")
        logger.info("Monitor with: tail -f \(logFilePath)")

        let server = Server(
            name: AppConstants.name,
            version: AppConstants.version,
            capabilities: .init(
                tools: .init()
            )
        )

        // v0.5.1: LSP状態管理
        let lspState = LSPState(logger: logger)

        var projectMemory: ProjectMemory?

        #if DEBUG
        // v0.5.3: デバッグランナー起動（5秒後に自動実行）
        Task.detached {
            await DebugRunner.run(
                delay: 5.0,
                lspState: lspState,
                logger: logger
            )
        }
        logger.info("🔧 DebugRunner enabled - automatic tests will start in 5 seconds")
        #endif

        // ツールリスト（v0.5.1: 動的生成対応）
        await server.withMethodHandler(ListTools.self) { _ in
            logger.info("ListTools handler called")
            var tools: [Tool] = []

            // SwiftSyntaxツール（常に利用可能）
            tools.append(contentsOf: [
                // v0.5.0: 新しい構造のツール
                InitializeProjectTool.toolDefinition,
                FindFilesTool.toolDefinition,
                SearchCodeTool.toolDefinition,
                ListSymbolsTool.toolDefinition,
                FindSymbolDefinitionTool.toolDefinition,
                AddNoteTool.toolDefinition,
                SearchNotesTool.toolDefinition,
                // v0.6.0で削除: GetProjectStats, ReadFunctionBody, ReadLines
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
                // v0.6.0で削除: ListDirectory, ReadFile
                // v0.5.0 新規ツール
                ThinkAboutAnalysisTool.toolDefinition
            ])

            // v0.5.2: LSPツール（常にツールリストに追加、実行時にLSP利用可能性をチェック）
            tools.append(FindSymbolReferencesTool.toolDefinition)

            let lspAvailable = await lspState.isLSPAvailable()
            logger.info("LSP status: \(lspAvailable ? "available" : "not available")")
            logger.info("Total tools: \(tools.count)")

            return ListTools.Result(tools: tools)
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

                // ProjectMemory初期化
                projectMemory = try ProjectMemory(projectPath: projectPath)

                // v0.5.1: LSP接続を試みる（バックグラウンド、非ブロッキング）
                Task {
                    let lspAvailable = await lspState.tryConnect(projectPath: projectPath)

                    if lspAvailable {
                        logger.info("✅ LSP available - Enhanced features ready")
                    } else {
                        logger.info("ℹ️ LSP unavailable - Using SwiftSyntax only")
                    }
                }

                // 即座にレスポンス返却（LSP接続を待たない）
                return CallTool.Result(content: [
                    .text("✅ Project initialized: \(projectPath)\n\nℹ️ Checking LSP availability in background...\n\n\(projectMemory?.getStats() ?? "")")
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

            // v0.6.0で削除: getProjectStats, readFunctionBody, readLines

            case ToolNames.listPropertyWrappers:
                return try await ListPropertyWrappersTool.execute(
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

            // v0.5.2 新規ツール
            case ToolNames.findSymbolReferences:
                return try await FindSymbolReferencesTool.execute(
                    params: params,
                    projectMemory: projectMemory,
                    lspState: lspState,
                    logger: logger
                )

            // v0.6.0で削除: listDirectory, readFile

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

