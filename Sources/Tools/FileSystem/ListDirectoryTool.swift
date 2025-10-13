//
//  ListDirectoryTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// ディレクトリ一覧ツール
///
/// ## 目的
/// プロジェクト構造の把握とファイル配置の確認
///
/// ## 効果
/// - プロジェクトのディレクトリ構造を理解
/// - ファイルの配置を確認
/// - 再帰オプションで階層全体を取得可能
/// - ファイル数の確認
///
/// ## 使用シーン
/// - プロジェクト初期の構造把握
/// - 特定ディレクトリ内のファイル確認
/// - アーキテクチャ分析の第一歩
/// - ディレクトリ構成の理解
///
/// ## 使用例
/// list_directory(path: "/path/to/project", recursive: false)
/// → Directory: /path/to/project
///   Mode: Non-recursive
///   Items: 15
///   App
///   Domain
///   Infrastructure
///   Tests
///   ...
///
/// ## パラメータ
/// - path: 一覧表示するディレクトリパス（必須）
/// - recursive: 再帰的に表示（オプション、デフォルト: false）
enum ListDirectoryTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.listDirectory,
            description: "List files and directories in a path",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    ParameterKeys.path: .object([
                        "type": .string("string"),
                        "description": .string("Directory path to list")
                    ]),
                    ParameterKeys.recursive: .object([
                        "type": .string("boolean"),
                        "description": .string("List recursively (optional, default: false)")
                    ])
                ]),
                "required": .array([.string(ParameterKeys.path)])
            ])
        )
    }

    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result {
        let path = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.path,
            errorMessage: ErrorMessages.missingPath
        )
        let isRecursive = ToolHelpers.getBool(from: params.arguments, key: ParameterKeys.recursive, defaultValue: false)

        guard FileManager.default.fileExists(atPath: path) else {
            throw MCPError.invalidParams(ErrorMessages.pathNotFound)
        }

        var entries: [String] = []

        if isRecursive {
            if let enumerator = FileManager.default.enumerator(atPath: path) {
                while let file = enumerator.nextObject() as? String {
                    entries.append(file)
                }
            }
        } else {
            entries = try FileManager.default.contentsOfDirectory(atPath: path)
        }

        let result = """
        Directory: \(path)
        Mode: \(isRecursive ? "Recursive" : "Non-recursive")
        Items: \(entries.count)

        \(entries.sorted().prefix(100).map { "  \($0)" }.joined(separator: "\n"))
        \(entries.count > 100 ? "\n... and \(entries.count - 100) more items" : "")
        """

        return CallTool.Result(content: [.text(result)])
    }
}
