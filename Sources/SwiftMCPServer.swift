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

        let logger = Logger(label: "swift-mcp-server")
        logger.info("Starting Swift MCP Server (Filesystem + SwiftSyntax)...")

        let server = Server(
            name: "SwiftCodeAnalyzer",
            version: "0.2.0",
            capabilities: .init(
                tools: .init()
            )
        )

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
                    name: "find_files",
                    description: "Find Swift files in the project by pattern (glob-like search)",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "pattern": .object([
                                "type": .string("string"),
                                "description": .string("File name pattern (e.g., '*Controller.swift', 'User*')")
                            ])
                        ]),
                        "required": .array([.string("pattern")])
                    ])
                ),
                Tool(
                    name: "search_code",
                    description: "Search code content using regex pattern (grep-like search)",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "pattern": .object([
                                "type": .string("string"),
                                "description": .string("Regex pattern to search for")
                            ]),
                            "file_pattern": .object([
                                "type": .string("string"),
                                "description": .string("Optional file pattern to limit search (e.g., '*.swift')")
                            ])
                        ]),
                        "required": .array([.string("pattern")])
                    ])
                ),
                Tool(
                    name: "list_symbols",
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
                ),
                Tool(
                    name: "find_symbol_definition",
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
                ),
                Tool(
                    name: "list_property_wrappers",
                    description: "List SwiftUI property wrappers (@State, @Binding, etc.) in a file",
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
                    name: "list_protocol_conformances",
                    description: "List protocol conformances and inheritance for types in a file",
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
                    name: "list_extensions",
                    description: "List extensions and their members in a file",
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
                    name: "analyze_imports",
                    description: "Analyze import dependencies across the project",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ])
                ),
                Tool(
                    name: "get_type_hierarchy",
                    description: "Get the inheritance hierarchy for a specific type",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "type_name": .object([
                                "type": .string("string"),
                                "description": .string("Name of the type to analyze")
                            ])
                        ]),
                        "required": .array([.string("type_name")])
                    ])
                ),
                Tool(
                    name: "find_test_cases",
                    description: "Find XCTest test cases and methods in the project",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:])
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

            case "find_files":
                guard let memory = projectMemory else {
                    throw MCPError.invalidRequest("Project not initialized")
                }
                guard let args = params.arguments,
                      let patternValue = args["pattern"] else {
                    throw MCPError.invalidParams("Missing pattern")
                }
                let pattern = String(describing: patternValue)
                let files = try FileSearcher.findFiles(in: memory.projectPath, pattern: pattern)

                let result = """
                Found \(files.count) files matching '\(pattern)':

                \(files.map { "  \($0)" }.joined(separator: "\n"))
                """

                return CallTool.Result(content: [.text(result)])

            case "search_code":
                guard let memory = projectMemory else {
                    throw MCPError.invalidRequest("Project not initialized")
                }
                guard let args = params.arguments,
                      let patternValue = args["pattern"] else {
                    throw MCPError.invalidParams("Missing pattern")
                }
                let pattern = String(describing: patternValue)
                let filePattern = args["file_pattern"].map { String(describing: $0) }

                let matches = try FileSearcher.searchCode(
                    in: memory.projectPath,
                    pattern: pattern,
                    filePattern: filePattern
                )

                var result = "Found \(matches.count) matches:\n\n"
                for match in matches {
                    result += "\(match.file):\(match.line): \(match.content.trimmingCharacters(in: .whitespaces))\n"
                }

                return CallTool.Result(content: [.text(result)])

            case "list_symbols":
                guard let args = params.arguments,
                      let filePathValue = args["file_path"] else {
                    throw MCPError.invalidParams("Missing file_path")
                }
                let filePath = String(describing: filePathValue)
                let symbols = try SwiftSyntaxAnalyzer.listSymbols(filePath: filePath)

                var result = "Symbols in \(filePath):\n\n"
                for symbol in symbols {
                    result += "[\(symbol.kind)] \(symbol.name) (line \(symbol.line))\n"
                }

                return CallTool.Result(content: [.text(result)])

            case "find_symbol_definition":
                guard let memory = projectMemory else {
                    throw MCPError.invalidRequest("Project not initialized")
                }
                guard let args = params.arguments,
                      let symbolNameValue = args["symbol_name"] else {
                    throw MCPError.invalidParams("Missing symbol_name")
                }
                let symbolName = String(describing: symbolNameValue)

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

            case "list_property_wrappers":
                guard let args = params.arguments,
                      let filePathValue = args["file_path"] else {
                    throw MCPError.invalidParams("Missing file_path")
                }
                let filePath = String(describing: filePathValue)
                let wrappers = try SwiftSyntaxAnalyzer.listPropertyWrappers(filePath: filePath)

                if wrappers.isEmpty {
                    return CallTool.Result(content: [.text("No property wrappers found in \(filePath)")])
                }

                var result = "Property Wrappers in \(filePath):\n\n"
                for wrapper in wrappers {
                    result += "[@\(wrapper.wrapperType)] \(wrapper.propertyName)"
                    if let typeName = wrapper.typeName {
                        result += ": \(typeName)"
                    }
                    result += " (line \(wrapper.line))\n"
                }

                return CallTool.Result(content: [.text(result)])

            case "list_protocol_conformances":
                guard let args = params.arguments,
                      let filePathValue = args["file_path"] else {
                    throw MCPError.invalidParams("Missing file_path")
                }
                let filePath = String(describing: filePathValue)
                let conformances = try SwiftSyntaxAnalyzer.listTypeConformances(filePath: filePath)

                if conformances.isEmpty {
                    return CallTool.Result(content: [.text("No type conformances found in \(filePath)")])
                }

                var result = "Protocol Conformances in \(filePath):\n\n"
                for conformance in conformances {
                    result += "[\(conformance.typeKind)] \(conformance.typeName) (line \(conformance.line))\n"

                    if let superclass = conformance.superclass {
                        result += "  Inherits from: \(superclass)\n"
                    }

                    if !conformance.protocols.isEmpty {
                        result += "  Conforms to: \(conformance.protocols.joined(separator: ", "))\n"
                    }

                    result += "\n"
                }

                return CallTool.Result(content: [.text(result)])

            case "list_extensions":
                guard let args = params.arguments,
                      let filePathValue = args["file_path"] else {
                    throw MCPError.invalidParams("Missing file_path")
                }
                let filePath = String(describing: filePathValue)
                let extensions = try SwiftSyntaxAnalyzer.listExtensions(filePath: filePath)

                if extensions.isEmpty {
                    return CallTool.Result(content: [.text("No extensions found in \(filePath)")])
                }

                var result = "Extensions in \(filePath):\n\n"
                for ext in extensions {
                    result += "[Extension] \(ext.extendedType) (line \(ext.line))\n"

                    if !ext.protocols.isEmpty {
                        result += "  Conforms to: \(ext.protocols.joined(separator: ", "))\n"
                    }

                    if !ext.members.isEmpty {
                        result += "  Members:\n"
                        for member in ext.members {
                            result += "    [\(member.kind)] \(member.name) (line \(member.line))\n"
                        }
                    }

                    result += "\n"
                }

                return CallTool.Result(content: [.text(result)])

            case "analyze_imports":
                guard let memory = projectMemory else {
                    throw MCPError.invalidRequest("Project not initialized")
                }

                let fileImports = try SwiftSyntaxAnalyzer.analyzeImports(projectPath: memory.projectPath, projectMemory: memory)

                if fileImports.isEmpty {
                    return CallTool.Result(content: [.text("No imports found in project")])
                }

                var result = "Import Dependencies Analysis:\n\n"

                // モジュールごとに集計
                var moduleUsage: [String: Int] = [:]
                for (_, imports) in fileImports {
                    for imp in imports {
                        moduleUsage[imp.module, default: 0] += 1
                    }
                }

                result += "Most used modules:\n"
                for (module, count) in moduleUsage.sorted(by: { $0.value > $1.value }).prefix(10) {
                    result += "  \(module): \(count) files\n"
                }
                result += "\n"

                result += "Files and their imports (\(fileImports.count) files):\n\n"
                for (file, imports) in fileImports.sorted(by: { $0.key < $1.key }).prefix(20) {
                    let fileName = (file as NSString).lastPathComponent
                    result += "\(fileName):\n"
                    for imp in imports {
                        result += "  └─ \(imp.module) (line \(imp.line))\n"
                    }
                    result += "\n"
                }

                if fileImports.count > 20 {
                    result += "... and \(fileImports.count - 20) more files\n"
                }

                return CallTool.Result(content: [.text(result)])

            case "get_type_hierarchy":
                guard let memory = projectMemory else {
                    throw MCPError.invalidRequest("Project not initialized")
                }
                guard let args = params.arguments,
                      let typeNameValue = args["type_name"] else {
                    throw MCPError.invalidParams("Missing type_name")
                }
                let typeName = String(describing: typeNameValue)

                guard let hierarchy = try SwiftSyntaxAnalyzer.getTypeHierarchy(
                    typeName: typeName,
                    projectPath: memory.projectPath,
                    projectMemory: memory
                ) else {
                    return CallTool.Result(content: [.text("Type '\(typeName)' not found in project")])
                }

                var result = "Type Hierarchy for '\(typeName)':\n\n"
                result += "[\(hierarchy.typeKind)] \(hierarchy.typeName)\n"
                result += "  Location: \(hierarchy.filePath):\(hierarchy.line)\n\n"

                if let superclass = hierarchy.superclass {
                    result += "Inherits from:\n"
                    result += "  └─ \(superclass)\n\n"
                }

                if !hierarchy.protocols.isEmpty {
                    result += "Conforms to:\n"
                    for proto in hierarchy.protocols {
                        result += "  └─ \(proto)\n"
                    }
                    result += "\n"
                }

                if !hierarchy.subclasses.isEmpty {
                    result += "Subclasses:\n"
                    for subclass in hierarchy.subclasses {
                        result += "  └─ \(subclass)\n"
                    }
                    result += "\n"
                }

                if !hierarchy.conformingTypes.isEmpty {
                    result += "Types conforming to this protocol:\n"
                    for type in hierarchy.conformingTypes {
                        result += "  └─ \(type)\n"
                    }
                    result += "\n"
                }

                return CallTool.Result(content: [.text(result)])

            case "find_test_cases":
                guard let memory = projectMemory else {
                    throw MCPError.invalidRequest("Project not initialized")
                }

                let testCases = try SwiftSyntaxAnalyzer.findTestCases(projectPath: memory.projectPath)

                if testCases.isEmpty {
                    return CallTool.Result(content: [.text("No XCTest cases found in project")])
                }

                var result = "XCTest Cases (\(testCases.count) classes):\n\n"

                for testClass in testCases {
                    let fileName = (testClass.filePath as NSString).lastPathComponent
                    result += "[TestClass] \(testClass.className)\n"
                    result += "  File: \(fileName):\(testClass.line)\n"

                    if !testClass.testMethods.isEmpty {
                        result += "  Test methods (\(testClass.testMethods.count)):\n"
                        for method in testClass.testMethods {
                            result += "    └─ \(method.name) (line \(method.line))\n"
                        }
                    } else {
                        result += "  No test methods found\n"
                    }

                    result += "\n"
                }

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

