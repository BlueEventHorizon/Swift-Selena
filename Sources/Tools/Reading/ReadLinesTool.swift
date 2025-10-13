//
//  ReadLinesTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// 行範囲読み取りツール
///
/// ## 目的
/// ファイルの特定の行範囲だけを効率的に読み取ります。
///
/// ## 効果
/// - コンテキスト効率的なファイル読み取り
/// - 大きなファイルから必要な部分だけ取得
/// - トークン使用量の削減
/// - 行番号による正確な範囲指定
///
/// ## 処理内容
/// - ファイル全体を読み込み
/// - 改行で分割
/// - start_lineからend_lineまでを抽出（1-indexed）
/// - Swiftコードブロックでフォーマット
///
/// ## 使用シーン
/// - list_symbolsで見つけたシンボルの周辺コードを確認
/// - エラーメッセージで示された行番号付近を読む
/// - 大きなファイルの一部分だけ確認したい時
/// - コードレビューで特定範囲を見たい時
///
/// ## 使用例
/// read_lines(file_path: "UserManager.swift", start_line: 15, end_line: 30)
/// → File: UserManager.swift
///   Lines: 15-30
///   ```swift
///   func createUser(name: String) {
///       let user = User(name: name)
///       database.save(user)
///   }
///   ```
///
///
/// ## 他のツールとの違い
/// - read_file: ファイル全体を読み取る
/// - read_lines: 行範囲のみ読み取る（コンテキスト効率的）
/// - read_function_body: 関数全体を読み取る（ブレースカウント）
enum ReadLinesTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.readLines,
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
        let startLine = ToolHelpers.getInt(from: params.arguments, key: ParameterKeys.startLine, defaultValue: 1)
        let endLine = ToolHelpers.getInt(from: params.arguments, key: ParameterKeys.endLine, defaultValue: 1)

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
    }
}
