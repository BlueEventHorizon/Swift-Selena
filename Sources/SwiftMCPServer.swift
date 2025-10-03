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

// MARK: - FileSearcher

enum FileSearcher {
    static func findFiles(in directory: String, pattern: String) throws -> [String] {
        var results: [String] = []
        let fileManager = FileManager.default

        let regex = try NSRegularExpression(
            pattern: wildcardToRegex(pattern),
            options: [.caseInsensitive]
        )

        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            throw NSError(domain: "FileSearcher", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to enumerate directory"
            ])
        }

        for case let file as String in enumerator {
            if file.hasSuffix(".swift") {
                let range = NSRange(file.startIndex..., in: file)
                if regex.firstMatch(in: file, range: range) != nil {
                    results.append((directory as NSString).appendingPathComponent(file))
                }
            }
        }

        return results.sorted()
    }

    static func searchCode(in directory: String, pattern: String, filePattern: String?) throws -> [(file: String, line: Int, content: String)] {
        var results: [(file: String, line: Int, content: String)] = []
        let fileManager = FileManager.default

        let regex = try NSRegularExpression(pattern: pattern, options: [])

        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            throw NSError(domain: "FileSearcher", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to enumerate directory"
            ])
        }

        for case let file as String in enumerator {
            let shouldSearch: Bool
            if let filePattern = filePattern {
                let fileRegex = try NSRegularExpression(
                    pattern: wildcardToRegex(filePattern),
                    options: [.caseInsensitive]
                )
                let range = NSRange(file.startIndex..., in: file)
                shouldSearch = fileRegex.firstMatch(in: file, range: range) != nil
            } else {
                shouldSearch = file.hasSuffix(".swift")
            }

            if shouldSearch {
                let fullPath = (directory as NSString).appendingPathComponent(file)
                if let content = try? String(contentsOfFile: fullPath) {
                    let lines = content.components(separatedBy: .newlines)
                    for (lineNumber, lineContent) in lines.enumerated() {
                        let range = NSRange(lineContent.startIndex..., in: lineContent)
                        if regex.firstMatch(in: lineContent, range: range) != nil {
                            results.append((file: fullPath, line: lineNumber + 1, content: lineContent))
                        }
                    }
                }
            }
        }

        return results
    }

    private static func wildcardToRegex(_ pattern: String) -> String {
        var result = "^"
        for char in pattern {
            switch char {
            case "*":
                result += ".*"
            case "?":
                result += "."
            case ".":
                result += "\\."
            default:
                result += String(char)
            }
        }
        result += "$"
        return result
    }
}

// MARK: - SwiftSyntaxAnalyzer

enum SwiftSyntaxAnalyzer {
    struct SymbolInfo {
        let name: String
        let kind: String
        let line: Int
    }

    struct PropertyWrapperInfo {
        let propertyName: String
        let wrapperType: String
        let typeName: String?
        let line: Int
    }

    struct TypeConformanceInfo {
        let typeName: String
        let typeKind: String  // Class, Struct, Enum, Actor
        let protocols: [String]
        let superclass: String?
        let line: Int
    }

    struct ExtensionInfo {
        let extendedType: String
        let protocols: [String]
        let line: Int
        let members: [MemberInfo]

        struct MemberInfo {
            let name: String
            let kind: String  // Function, Variable, etc.
            let line: Int
        }
    }

    static func listSymbols(filePath: String) throws -> [SymbolInfo] {
        let content = try String(contentsOfFile: filePath)
        let sourceFile = Parser.parse(source: content)

        let visitor = SymbolVisitor(converter: SourceLocationConverter(fileName: filePath, tree: sourceFile))
        visitor.walk(sourceFile)

        return visitor.symbols
    }

    static func listPropertyWrappers(filePath: String) throws -> [PropertyWrapperInfo] {
        let content = try String(contentsOfFile: filePath)
        let sourceFile = Parser.parse(source: content)

        let visitor = PropertyWrapperVisitor(converter: SourceLocationConverter(fileName: filePath, tree: sourceFile))
        visitor.walk(sourceFile)

        return visitor.propertyWrappers
    }

    static func listTypeConformances(filePath: String) throws -> [TypeConformanceInfo] {
        let content = try String(contentsOfFile: filePath)
        let sourceFile = Parser.parse(source: content)

        let visitor = TypeConformanceVisitor(converter: SourceLocationConverter(fileName: filePath, tree: sourceFile))
        visitor.walk(sourceFile)

        return visitor.typeConformances
    }

    static func listExtensions(filePath: String) throws -> [ExtensionInfo] {
        let content = try String(contentsOfFile: filePath)
        let sourceFile = Parser.parse(source: content)

        let visitor = ExtensionVisitor(converter: SourceLocationConverter(fileName: filePath, tree: sourceFile))
        visitor.walk(sourceFile)

        return visitor.extensions
    }

    private class SymbolVisitor: SyntaxVisitor {
        var symbols: [SymbolInfo] = []
        let converter: SourceLocationConverter

        init(converter: SourceLocationConverter) {
            self.converter = converter
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            let location = node.startLocation(converter: converter)
            symbols.append(SymbolInfo(
                name: node.name.text,
                kind: "Class",
                line: location.line
            ))
            return .visitChildren
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            let location = node.startLocation(converter: converter)
            symbols.append(SymbolInfo(
                name: node.name.text,
                kind: "Struct",
                line: location.line
            ))
            return .visitChildren
        }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            let location = node.startLocation(converter: converter)
            symbols.append(SymbolInfo(
                name: node.name.text,
                kind: "Enum",
                line: location.line
            ))
            return .visitChildren
        }

        override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
            let location = node.startLocation(converter: converter)
            symbols.append(SymbolInfo(
                name: node.name.text,
                kind: "Protocol",
                line: location.line
            ))
            return .visitChildren
        }

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            let location = node.startLocation(converter: converter)
            symbols.append(SymbolInfo(
                name: node.name.text,
                kind: "Function",
                line: location.line
            ))
            return .visitChildren
        }

        override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
            let location = node.startLocation(converter: converter)
            for binding in node.bindings {
                if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                    symbols.append(SymbolInfo(
                        name: identifier.identifier.text,
                        kind: "Variable",
                        line: location.line
                    ))
                }
            }
            return .visitChildren
        }
    }

    private class PropertyWrapperVisitor: SyntaxVisitor {
        var propertyWrappers: [PropertyWrapperInfo] = []
        let converter: SourceLocationConverter

        init(converter: SourceLocationConverter) {
            self.converter = converter
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
            let location = node.startLocation(converter: converter)

            // Check for attributes (like @State, @Binding, etc.)
            for attribute in node.attributes {
                if let customAttribute = attribute.as(AttributeSyntax.self) {
                    let wrapperType = customAttribute.attributeName.trimmedDescription

                    // Only process known SwiftUI property wrappers
                    let knownWrappers = ["State", "Binding", "ObservedObject", "StateObject",
                                        "EnvironmentObject", "Environment", "Published",
                                        "FetchRequest", "AppStorage", "SceneStorage",
                                        "ObservationTracked", "ObservationIgnored"]

                    if knownWrappers.contains(wrapperType) {
                        for binding in node.bindings {
                            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                                let typeName = binding.typeAnnotation?.type.trimmedDescription
                                propertyWrappers.append(PropertyWrapperInfo(
                                    propertyName: identifier.identifier.text,
                                    wrapperType: wrapperType,
                                    typeName: typeName,
                                    line: location.line
                                ))
                            }
                        }
                    }
                }
            }

            return .visitChildren
        }
    }

    private class TypeConformanceVisitor: SyntaxVisitor {
        var typeConformances: [TypeConformanceInfo] = []
        let converter: SourceLocationConverter

        init(converter: SourceLocationConverter) {
            self.converter = converter
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            let location = node.startLocation(converter: converter)
            let (protocols, superclass) = extractInheritance(from: node.inheritanceClause)

            typeConformances.append(TypeConformanceInfo(
                typeName: node.name.text,
                typeKind: "Class",
                protocols: protocols,
                superclass: superclass,
                line: location.line
            ))

            return .visitChildren
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            let location = node.startLocation(converter: converter)
            let (protocols, _) = extractInheritance(from: node.inheritanceClause)

            typeConformances.append(TypeConformanceInfo(
                typeName: node.name.text,
                typeKind: "Struct",
                protocols: protocols,
                superclass: nil,
                line: location.line
            ))

            return .visitChildren
        }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            let location = node.startLocation(converter: converter)
            let (protocols, _) = extractInheritance(from: node.inheritanceClause)

            typeConformances.append(TypeConformanceInfo(
                typeName: node.name.text,
                typeKind: "Enum",
                protocols: protocols,
                superclass: nil,
                line: location.line
            ))

            return .visitChildren
        }

        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
            let location = node.startLocation(converter: converter)
            let (protocols, superclass) = extractInheritance(from: node.inheritanceClause)

            typeConformances.append(TypeConformanceInfo(
                typeName: node.name.text,
                typeKind: "Actor",
                protocols: protocols,
                superclass: superclass,
                line: location.line
            ))

            return .visitChildren
        }

        private func extractInheritance(from clause: InheritanceClauseSyntax?) -> (protocols: [String], superclass: String?) {
            guard let clause = clause else {
                return ([], nil)
            }

            var protocols: [String] = []
            var superclass: String? = nil

            // 最初の要素がクラス名（大文字始まり）の場合はスーパークラスの可能性
            let inheritedTypes = clause.inheritedTypes.map { $0.type.trimmedDescription }

            for (index, type) in inheritedTypes.enumerated() {
                // 最初の要素で大文字始まりの場合、スーパークラスの可能性
                // ただし、プロトコルも大文字始まりなので、正確な判別は難しい
                // ここでは全てプロトコルとして扱い、必要に応じてスーパークラスを分離
                if index == 0 && type.first?.isUppercase == true {
                    // 一般的なプロトコル名でなければスーパークラスとして扱う
                    let commonProtocols = ["View", "ObservableObject", "Identifiable", "Codable",
                                         "Equatable", "Hashable", "Comparable", "CustomStringConvertible"]
                    if !commonProtocols.contains(type) && !type.contains("Delegate") && !type.contains("Protocol") {
                        superclass = type
                        continue
                    }
                }
                protocols.append(type)
            }

            return (protocols, superclass)
        }
    }

    private class ExtensionVisitor: SyntaxVisitor {
        var extensions: [ExtensionInfo] = []
        let converter: SourceLocationConverter

        init(converter: SourceLocationConverter) {
            self.converter = converter
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
            let location = node.startLocation(converter: converter)
            let extendedType = node.extendedType.trimmedDescription

            // プロトコル準拠を取得
            var protocols: [String] = []
            if let inheritanceClause = node.inheritanceClause {
                protocols = inheritanceClause.inheritedTypes.map { $0.type.trimmedDescription }
            }

            // Extension内のメンバーを取得
            var members: [ExtensionInfo.MemberInfo] = []
            for member in node.memberBlock.members {
                if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                    let memberLocation = funcDecl.startLocation(converter: converter)
                    members.append(ExtensionInfo.MemberInfo(
                        name: funcDecl.name.text,
                        kind: "Function",
                        line: memberLocation.line
                    ))
                } else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                    let memberLocation = varDecl.startLocation(converter: converter)
                    for binding in varDecl.bindings {
                        if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                            members.append(ExtensionInfo.MemberInfo(
                                name: identifier.identifier.text,
                                kind: "Variable",
                                line: memberLocation.line
                            ))
                        }
                    }
                } else if let initDecl = member.decl.as(InitializerDeclSyntax.self) {
                    let memberLocation = initDecl.startLocation(converter: converter)
                    members.append(ExtensionInfo.MemberInfo(
                        name: "init",
                        kind: "Initializer",
                        line: memberLocation.line
                    ))
                }
            }

            extensions.append(ExtensionInfo(
                extendedType: extendedType,
                protocols: protocols,
                line: location.line,
                members: members
            ))

            return .visitChildren
        }
    }
}
