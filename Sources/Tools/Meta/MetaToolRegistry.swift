//
//  MetaToolRegistry.swift
//  Swift-Selena
//
//  Created on 2025/12/14.
//
//  Purpose: Anthropicの「コード実行パターン」適用
//  - 全ツールの簡易リスト（名前 + 1行説明）を提供
//  - ツール名からTool定義を取得する機能を提供
//

import Foundation
import MCP

/// メタツールレジストリ
///
/// 全ツールの情報を管理し、動的ロードを可能にする
enum MetaToolRegistry {

    /// ツールの簡易情報
    struct ToolSummary {
        let name: String
        let description: String
        let category: String
    }

    /// カテゴリ定義
    enum Category: String, CaseIterable {
        case searchFiles = "Search & Files"
        case symbols = "Symbols"
        case swiftUI = "SwiftUI"
        case analysis = "Analysis"

        var displayName: String { rawValue }
    }

    /// 全ツールの簡易リスト（initialize_projectは除く - 常に直接公開されるため）
    static let toolSummaries: [ToolSummary] = [
        // Search & Files
        ToolSummary(
            name: ToolNames.findFiles,
            description: "Find files by pattern (glob-like)",
            category: Category.searchFiles.rawValue
        ),
        ToolSummary(
            name: ToolNames.searchCode,
            description: "Search code content (grep-like)",
            category: Category.searchFiles.rawValue
        ),
        ToolSummary(
            name: ToolNames.searchFilesWithoutPattern,
            description: "Find files NOT matching pattern",
            category: Category.searchFiles.rawValue
        ),

        // Symbols
        ToolSummary(
            name: ToolNames.listSymbols,
            description: "List all symbols in a file",
            category: Category.symbols.rawValue
        ),
        ToolSummary(
            name: ToolNames.findSymbolDefinition,
            description: "Find where a symbol is defined",
            category: Category.symbols.rawValue
        ),

        // SwiftUI
        ToolSummary(
            name: ToolNames.listPropertyWrappers,
            description: "List @State, @Binding etc.",
            category: Category.swiftUI.rawValue
        ),
        ToolSummary(
            name: ToolNames.listProtocolConformances,
            description: "List protocol conformances",
            category: Category.swiftUI.rawValue
        ),
        ToolSummary(
            name: ToolNames.listExtensions,
            description: "List extensions in a file",
            category: Category.swiftUI.rawValue
        ),

        // Analysis
        ToolSummary(
            name: ToolNames.analyzeImports,
            description: "Analyze import dependencies",
            category: Category.analysis.rawValue
        ),
        ToolSummary(
            name: ToolNames.getTypeHierarchy,
            description: "Get type inheritance hierarchy",
            category: Category.analysis.rawValue
        ),
        ToolSummary(
            name: ToolNames.findTestCases,
            description: "Find XCTest cases",
            category: Category.analysis.rawValue
        )
    ]

    /// ツール名から完全なTool定義を取得
    /// - Parameter name: ツール名
    /// - Returns: Tool定義（見つからない場合はnil）
    static func getToolDefinition(_ name: String) -> Tool? {
        switch name {
        case ToolNames.initializeProject:
            return InitializeProjectTool.toolDefinition
        case ToolNames.findFiles:
            return FindFilesTool.toolDefinition
        case ToolNames.searchCode:
            return SearchCodeTool.toolDefinition
        case ToolNames.searchFilesWithoutPattern:
            return SearchFilesWithoutPatternTool.toolDefinition
        case ToolNames.listSymbols:
            return ListSymbolsTool.toolDefinition
        case ToolNames.findSymbolDefinition:
            return FindSymbolDefinitionTool.toolDefinition
        case ToolNames.listPropertyWrappers:
            return ListPropertyWrappersTool.toolDefinition
        case ToolNames.listProtocolConformances:
            return ListProtocolConformancesTool.toolDefinition
        case ToolNames.listExtensions:
            return ListExtensionsTool.toolDefinition
        case ToolNames.analyzeImports:
            return AnalyzeImportsTool.toolDefinition
        case ToolNames.getTypeHierarchy:
            return GetTypeHierarchyTool.toolDefinition
        case ToolNames.findTestCases:
            return FindTestCasesTool.toolDefinition
        default:
            return nil
        }
    }

    /// カテゴリ別にグループ化した出力を生成
    static func formatToolList() -> String {
        var result = "Available Swift-Selena Tools (\(toolSummaries.count) tools):\n\n"

        for category in Category.allCases {
            let toolsInCategory = toolSummaries.filter { $0.category == category.rawValue }
            if !toolsInCategory.isEmpty {
                result += "\(category.displayName):\n"
                for tool in toolsInCategory {
                    result += "- \(tool.name): \(tool.description)\n"
                }
                result += "\n"
            }
        }

        result += "Use get_tool_schema(tool_name) to get full parameter schema.\n"
        result += "Use execute_tool(tool_name, params) to run a tool."

        return result
    }

    /// ツール名の一覧を取得
    static var allToolNames: [String] {
        toolSummaries.map { $0.name }
    }
}
