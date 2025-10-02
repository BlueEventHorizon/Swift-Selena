import MCP
import Foundation
import Logging

@main
struct SwiftMCPServer {
    static func main() async throws {
        // ロギング設定
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = .info
            return handler
        }
        
        let logger = Logger(label: "swift-mcp-server")
        logger.info("Starting Swift MCP Server with SourceKit-LSP...")
        
        let server = Server(
            name: "SwiftCodeAnalyzer",
            version: "0.1.0",
            capabilities: .init(
                tools: .init()
            )
        )
        
        // グローバルなLSPクライアントとメモリ
        let lspClient = SourceKitLSPClient()
        var projectMemory: ProjectMemory?
        
        // ツールリスト
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                Tool(
                    name: "initialize_project",
                    description: "Initialize a Swift project for analysis. Must be called first.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "project_path": .object([
                                "type": .string("string"),
                                "description": .string("Absolute path to Swift project root")
                            ])
                        ]),
                        "required": .array([.string("project_path")])
                    ])
                ),
                Tool(
                    name: "find_symbol",
                    description: "Find a symbol (class, function, protocol, etc.) in the project",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "query": .object([
                                "type": .string("string"),
                                "description": .string("Symbol name to search for")
                            ])
                        ]),
                        "required": .array([.string("query")])
                    ])
                ),
                Tool(
                    name: "get_document_symbols",
                    description: "Get all symbols in a specific file",
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
                ),
                Tool(
                    name: "get_definition",
                    description: "Get the definition location of a symbol",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "file_path": .object([
                                "type": .string("string"),
                                "description": .string("File containing the symbol")
                            ]),
                            "line": .object([
                                "type": .string("integer"),
                                "description": .string("Line number (0-indexed)")
                            ]),
                            "column": .object([
                                "type": .string("integer"),
                                "description": .string("Column number (0-indexed)")
                            ])
                        ]),
                        "required": .array([.string("file_path"), .string("line"), .string("column")])
                    ])
                ),
                Tool(
                    name: "find_references",
                    description: "Find all references to a symbol",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "file_path": .object([
                                "type": .string("string"),
                                "description": .string("File containing the symbol")
                            ]),
                            "line": .object([
                                "type": .string("integer"),
                                "description": .string("Line number (0-indexed)")
                            ]),
                            "column": .object([
                                "type": .string("integer"),
                                "description": .string("Column number (0-indexed)")
                            ])
                        ]),
                        "required": .array([.string("file_path"), .string("line"), .string("column")])
                    ])
                ),
                Tool(
                    name: "add_note",
                    description: "Add a note about the project (persisted across sessions)",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "content": .object([
                                "type": .string("string"),
                                "description": .string("Note content")
                            ]),
                            "tags": .object([
                                "type": .string("array"),
                                "items": .object([
                                    "type": .string("string")
                                ]),
                                "description": .string("Optional tags for categorization")
                            ])
                        ]),
                        "required": .array([.string("content")])
                    ])
                ),
                Tool(
                    name: "search_notes",
                    description: "Search through saved notes",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "query": .object([
                                "type": .string("string"),
                                "description": .string("Search query")
                            ])
                        ]),
                        "required": .array([.string("query")])
                    ])
                ),
                Tool(
                    name: "get_project_stats",
                    description: "Get project statistics and memory information",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ])
                ),
                Tool(
                    name: "read_function_body",
                    description: "Read only the implementation of a specific function (context-efficient)",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "file_path": .object([
                                "type": .string("string"),
                                "description": .string("File containing the function")
                            ]),
                            "function_name": .object([
                                "type": .string("string"),
                                "description": .string("Name of the function to read")
                            ])
                        ]),
                        "required": .array([.string("file_path"), .string("function_name")])
                    ])
                ),
                Tool(
                    name: "read_lines",
                    description: "Read specific lines from a file (context-efficient)",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "file_path": .object([
                                "type": .string("string"),
                                "description": .string("File to read")
                            ]),
                            "start_line": .object([
                                "type": .string("integer"),
                                "description": .string("Start line (1-indexed)")
                            ]),
                            "end_line": .object([
                                "type": .string("integer"),
                                "description": .string("End line (1-indexed)")
                            ])
                        ]),
                        "required": .array([.string("file_path"), .string("start_line"), .string("end_line")])
                    ])
                )
            ])
        }
        
        // ツール実行
        await server.withMethodHandler(CallTool.self) { params in
            logger.info("Tool called: \(params.name)")
            
            switch params.name {
            case "initialize_project":
                guard let args = params.arguments,
                      let projectPathValue = args["project_path"] else {
                    throw MCPError.invalidParams("Missing project_path")
                }
                let projectPath = String(describing: projectPathValue)
                try await lspClient.initialize(projectPath: projectPath)
                
                projectMemory = try ProjectMemory(projectPath: projectPath)
                
                return CallTool.Result(content: [
                    .text("✅ Project initialized: \(projectPath)\n\n\(projectMemory?.getStats() ?? "")")
                ])
                
            case "find_symbol":
                guard let args = params.arguments,
                      let queryValue = args["query"] else {
                    throw MCPError.invalidParams("Missing query")
                }
                let query = String(describing: queryValue)
                let result = try await lspClient.findSymbol(query: query)
                return CallTool.Result(content: [.text(result)])
                
            case "get_document_symbols":
                guard let args = params.arguments,
                      let filePathValue = args["file_path"] else {
                    throw MCPError.invalidParams("Missing file_path")
                }
                let filePath = String(describing: filePathValue)
                let result = try await lspClient.getDocumentSymbols(filePath: filePath)
                return CallTool.Result(content: [.text(result)])
                
            case "get_definition":
                guard let args = params.arguments,
                      let filePathValue = args["file_path"],
                      let lineValue = args["line"],
                      let columnValue = args["column"] else {
                    throw MCPError.invalidParams("Missing required parameters")
                }
                let filePath = String(describing: filePathValue)
                let line = Int(String(describing: lineValue)) ?? 0
                let column = Int(String(describing: columnValue)) ?? 0
                
                let result = try await lspClient.getDefinition(
                    filePath: filePath,
                    line: line,
                    column: column
                )
                return CallTool.Result(content: [.text(result)])
                
            case "find_references":
                guard let args = params.arguments,
                      let filePathValue = args["file_path"],
                      let lineValue = args["line"],
                      let columnValue = args["column"] else {
                    throw MCPError.invalidParams("Missing required parameters")
                }
                let filePath = String(describing: filePathValue)
                let line = Int(String(describing: lineValue)) ?? 0
                let column = Int(String(describing: columnValue)) ?? 0
                
                let result = try await lspClient.findReferences(
                    filePath: filePath,
                    line: line,
                    column: column
                )
                return CallTool.Result(content: [.text(result)])
                
            case "add_note":
                guard let memory = projectMemory else {
                    throw MCPError.invalidRequest("Project not initialized")
                }
                guard let args = params.arguments,
                      let contentValue = args["content"] else {
                    throw MCPError.invalidParams("Missing content")
                }
                let content = String(describing: contentValue)
                
                var tags: [String] = []
                if let tagsValue = args["tags"] {
                    let tagsStr = String(describing: tagsValue)
                    // 簡易的な配列パース（実際にはもっと堅牢な実装が必要）
                    tags = tagsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                }
                
                memory.addNote(content: content, tags: tags)
                try memory.save()
                
                return CallTool.Result(content: [
                    .text("✅ Note saved: \(content)")
                ])
                
            case "search_notes":
                guard let memory = projectMemory else {
                    throw MCPError.invalidRequest("Project not initialized")
                }
                guard let args = params.arguments,
                      let queryValue = args["query"] else {
                    throw MCPError.invalidParams("Missing query")
                }
                let query = String(describing: queryValue)
                
                let notes = memory.searchNotes(query: query)
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                
                var result = "Found \(notes.count) notes:\n\n"
                for note in notes {
                    result += "[\(formatter.string(from: note.timestamp))] \(note.content)\n"
                    if !note.tags.isEmpty {
                        result += "  Tags: \(note.tags.joined(separator: ", "))\n"
                    }
                    result += "\n"
                }
                
                return CallTool.Result(content: [.text(result)])
                
            case "get_project_stats":
                guard let memory = projectMemory else {
                    throw MCPError.invalidRequest("Project not initialized")
                }
                
                return CallTool.Result(content: [
                    .text(memory.getStats())
                ])
                
            case "read_function_body":
                guard let args = params.arguments,
                      let filePathValue = args["file_path"],
                      let functionNameValue = args["function_name"] else {
                    throw MCPError.invalidParams("Missing required parameters")
                }
                let filePath = String(describing: filePathValue)
                let functionName = String(describing: functionNameValue)
                
                let content = try String(contentsOfFile: filePath)
                let lines = content.components(separatedBy: .newlines)
                
                var functionLines: [String] = []
                var capturing = false
                var braceCount = 0
                
                for line in lines {
                    if !capturing && line.contains("func \(functionName)") {
                        capturing = true
                    }
                    
                    if capturing {
                        functionLines.append(line)
                        braceCount += line.filter { $0 == "{" }.count
                        braceCount -= line.filter { $0 == "}" }.count
                        
                        if braceCount == 0 && functionLines.count > 1 {
                            break
                        }
                    }
                }
                
                if functionLines.isEmpty {
                    return CallTool.Result(content: [
                        .text("Function '\(functionName)' not found in \(filePath)")
                    ])
                }
                
                let result = """
                Function: \(functionName)
                Location: \(filePath)
                Lines: \(functionLines.count)
                
                ```swift
                \(functionLines.joined(separator: "\n"))
                ```
                """
                
                return CallTool.Result(content: [.text(result)])
                
            case "read_lines":
                guard let args = params.arguments,
                      let filePathValue = args["file_path"],
                      let startLineValue = args["start_line"],
                      let endLineValue = args["end_line"] else {
                    throw MCPError.invalidParams("Missing required parameters")
                }
                let filePath = String(describing: filePathValue)
                let startLine = Int(String(describing: startLineValue)) ?? 1
                let endLine = Int(String(describing: endLineValue)) ?? 1
                
                let content = try String(contentsOfFile: filePath)
                let lines = content.components(separatedBy: .newlines)
                
                guard startLine > 0, endLine <= lines.count, startLine <= endLine else {
                    throw MCPError.invalidParams("Invalid line range")
                }
                
                let selectedLines = lines[(startLine - 1)..<endLine]
                let result = """
                File: \(filePath)
                Lines: \(startLine)-\(endLine)
                
                ```swift
                \(selectedLines.joined(separator: "\n"))
                ```
                """
                
                return CallTool.Result(content: [.text(result)])
                
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
