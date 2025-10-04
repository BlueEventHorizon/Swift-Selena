//
//  Constants.swift
//  SwiftMCPServer
//
//  Created by k_terada on 2025/10/03.
//

import Foundation

/// アプリケーション全体の定数
enum AppConstants {
    static let name = "Swift-Selena"
    static let version = "0.4.0"
    static let loggerLabel = "swift-selena"
    static let storageDirectory = ".swift-selena"
}

/// MCPツール名の定数
enum ToolNames {
    static let initializeProject = "initialize_project"
    static let findFiles = "find_files"
    static let searchCode = "search_code"
    static let listSymbols = "list_symbols"
    static let findSymbolDefinition = "find_symbol_definition"
    static let addNote = "add_note"
    static let searchNotes = "search_notes"
    static let getProjectStats = "get_project_stats"
    static let readFunctionBody = "read_function_body"
    static let readLines = "read_lines"
    static let listPropertyWrappers = "list_property_wrappers"
    static let listProtocolConformances = "list_protocol_conformances"
    static let listExtensions = "list_extensions"
    static let analyzeImports = "analyze_imports"
    static let getTypeHierarchy = "get_type_hierarchy"
    static let findTestCases = "find_test_cases"
    static let findTypeUsages = "find_type_usages"
}

/// パラメータキーの定数
enum ParameterKeys {
    static let projectPath = "project_path"
    static let filePath = "file_path"
    static let pattern = "pattern"
    static let filePattern = "file_pattern"
    static let symbolName = "symbol_name"
    static let content = "content"
    static let tags = "tags"
    static let query = "query"
    static let functionName = "function_name"
    static let startLine = "start_line"
    static let endLine = "end_line"
    static let typeName = "type_name"
}

/// エラーメッセージの定数
enum ErrorMessages {
    static let projectNotInitialized = "Project not initialized"
    static let missingProjectPath = "Missing project_path"
    static let missingFilePath = "Missing file_path"
    static let missingPattern = "Missing pattern"
    static let missingSymbolName = "Missing symbol_name"
    static let missingContent = "Missing content"
    static let missingQuery = "Missing query"
    static let missingRequiredParameters = "Missing required parameters"
    static let missingTypeName = "Missing type_name"
    static let projectPathNotDirectory = "Project path does not exist or is not a directory"
}
