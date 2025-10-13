//
//  ReadFileTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// ファイル読み取りツール
///
/// ## 目的
/// あらゆる種類のファイルを読み取り（Swiftファイル以外にも対応）
///
/// ## 効果
/// - 設定ファイル（JSON, YAML, plist等）の読み取り
/// - ドキュメントファイル（Markdown, txt）の読み取り
/// - Swiftファイルも読み取り可能
/// - ファイル全体を一度に取得
///
/// ## 使用シーン
/// - Package.swiftの内容確認
/// - Info.plistの設定確認
/// - README.mdの確認
/// - .swift-versionの確認
/// - 設定ファイルの読み取り
///
/// ## 使用例
/// read_file(file_path: "Package.swift")
/// → File: Package.swift
///   Lines: 45
///   ```
///   // swift-tools-version: 5.9
///   import PackageDescription
///   ...
///   ```
///
/// ## 他のツールとの違い
/// - read_file: ファイル全体を読み取り
/// - read_lines: 指定行範囲のみ読み取り（コンテキスト効率的）
/// - read_symbol: 特定シンボルのみ読み取り（Swiftファイル専用）
enum ReadFileTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.readFile,
            description: "Read entire file content (works with any file type)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    ParameterKeys.filePath: .object([
                        "type": .string("string"),
                        "description": .string("Path to file")
                    ])
                ]),
                "required": .array([.string(ParameterKeys.filePath)])
            ])
        )
    }

    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result {
        let filePath = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.filePath,
            errorMessage: ErrorMessages.missingFilePath
        )

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw MCPError.invalidParams("File not found: \(filePath)")
        }

        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let lineCount = content.components(separatedBy: .newlines).count

        let result = """
        File: \(filePath)
        Lines: \(lineCount)

        ```
        \(content)
        ```
        """

        return CallTool.Result(content: [.text(result)])
    }
}
