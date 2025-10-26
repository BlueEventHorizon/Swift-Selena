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
    static let version = "0.5.3"
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
    // v0.6.0で削除: get_project_stats, read_function_body, read_lines（価値が低い、または代替可能）
    static let listPropertyWrappers = "list_property_wrappers"
    static let listProtocolConformances = "list_protocol_conformances"
    static let listExtensions = "list_extensions"
    static let analyzeImports = "analyze_imports"
    static let getTypeHierarchy = "get_type_hierarchy"
    static let findTestCases = "find_test_cases"
    static let findTypeUsages = "find_type_usages"

    // v0.5.0 新規ツール
    static let setAnalysisMode = "set_analysis_mode"
    static let readSymbol = "read_symbol"
    static let thinkAboutAnalysis = "think_about_analysis"  // v0.6.2でPrompts移行予定

    // v0.5.2 新規ツール
    static let findSymbolReferences = "find_symbol_references"  // LSPツール

    // v0.6.0で削除: list_directory, read_file（Claude標準機能で代替）
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

    // v0.5.0 新規パラメータ
    static let mode = "mode"
    static let symbolPath = "symbol_path"
    static let path = "path"
    static let recursive = "recursive"
    static let includeChildren = "include_children"

    // v0.5.2 新規パラメータ（LSP用）
    static let line = "line"
    static let column = "column"
}

/// 除外するディレクトリパターン（v0.5.4）
enum ExcludedDirectories {
    /// 除外するディレクトリ名
    static let patterns = [
        ".build",           // Swift Package Manager build artifacts
        "checkouts",        // SPM dependencies
        "DerivedData",      // Xcode build cache
        ".git",             // Git repository
        "Pods",             // CocoaPods dependencies
        "Carthage",         // Carthage dependencies
        ".swiftpm",         // SPM configuration
        "xcuserdata"        // Xcode user data
    ]

    /// パスが除外対象か判定
    static func shouldExclude(_ path: String) -> Bool {
        return patterns.contains { path.contains("/\($0)/") || path.hasSuffix("/\($0)") }
    }
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
    static let missingFunctionName = "Missing function_name"
    static let missingRequiredParameters = "Missing required parameters"
    static let missingTypeName = "Missing type_name"
    static let projectPathNotDirectory = "Project path does not exist or is not a directory"

    // v0.5.0 新規エラーメッセージ
    static let missingMode = "Missing mode parameter"
    static let missingPath = "Missing path parameter"
    static let missingSymbolPath = "Missing symbol_path parameter"
    static let invalidMode = "Invalid mode. Valid modes: general, swiftui, architecture, testing, refactoring"
    static let symbolNotFound = "Symbol not found"
    static let pathNotFound = "Path not found"
}
