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
    static let version = "0.6.3"
    static let loggerLabel = "swift-selena"
    static let storageDirectory = ".swift-selena"
}

/// MCPツール名の定数
enum ToolNames {
    static let initializeProject = "initialize_project"
    static let findFiles = "find_files"
    static let searchCode = "search_code"
    static let searchFilesWithoutPattern = "search_files_without_pattern"
    static let listSymbols = "list_symbols"
    static let findSymbolDefinition = "find_symbol_definition"
    static let listPropertyWrappers = "list_property_wrappers"
    static let listProtocolConformances = "list_protocol_conformances"
    static let listExtensions = "list_extensions"
    static let analyzeImports = "analyze_imports"
    static let getTypeHierarchy = "get_type_hierarchy"
    static let findTestCases = "find_test_cases"
}

/// メタツール名の定数（v0.6.3: コード実行パターン）
enum MetaToolNames {
    static let listAvailableTools = "list_available_tools"
    static let getToolSchema = "get_tool_schema"
    static let executeTool = "execute_tool"
}

/// メタツール用パラメータキーの定数
enum MetaParameterKeys {
    static let toolName = "tool_name"
    static let params = "params"
}

/// 環境変数キーの定数
enum EnvironmentKeys {
    /// SWIFT_SELENA_LEGACY=1 で従来モード（全ツール公開）
    static let legacyMode = "SWIFT_SELENA_LEGACY"
}

/// パラメータキーの定数
enum ParameterKeys {
    static let projectPath = "project_path"
    static let filePath = "file_path"
    static let pattern = "pattern"
    static let filePattern = "file_pattern"
    static let symbolName = "symbol_name"
    static let typeName = "type_name"
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
    static let missingTypeName = "Missing type_name"
    static let projectPathNotDirectory = "Project path does not exist or is not a directory"
}
