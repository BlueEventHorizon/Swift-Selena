//
//  ReadFunctionBodyTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// 関数本体読み取りツール
///
/// ## 目的
/// 指定した関数の実装部分だけを効率的に読み取ります。
///
/// ## 効果
/// - 関数の実装だけを取得（ファイル全体を読まない）
/// - トークン使用量の削減
/// - 関数の動作を素早く理解
/// - ブレースカウントによる正確な範囲抽出
///
/// ## 処理内容
/// - ファイル全体を読み込み
/// - `func 関数名`を含む行を検索
/// - ブレースカウントで関数の開始から終了まで抽出
/// - 開き波括弧と閉じ波括弧をカウントして範囲を特定
/// - 関数定義全体（シグネチャ+本体）を返却
///
/// ## 使用シーン
/// - 特定の関数の実装を確認したい時
/// - list_symbolsで見つけた関数の詳細を知りたい時
/// - バグ修正で関数の動作を理解したい時
/// - 大きなファイルから関数だけ抽出したい時
///
/// ## 使用例
/// read_function_body(file_path: "UserManager.swift", function_name: "createUser")
/// → Function: createUser
///   Location: UserManager.swift
///   Lines: 8
///
///   ```swift
///   func createUser(name: String) {
///       let user = User(name: name)
///       database.save(user)
///       notificationCenter.post(.userCreated)
///   }
///   ```
///
///
/// ## 他のツールとの違い
/// - read_file: ファイル全体を読む（大量のトークン消費）
/// - read_lines: 行番号指定で読む（行番号を知っている必要あり）
/// - read_function_body: 関数名で読む（自動で範囲抽出）
///
/// ## 制限事項
/// - シンプルなブレースカウントを使用（文字列内の波括弧も誤検出の可能性）
/// - 同名の関数が複数ある場合は最初の1つのみ
/// - より高精度な解析にはread_symbolを使用
enum ReadFunctionBodyTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.readFunctionBody,
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
        let functionName = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.functionName,
            errorMessage: ErrorMessages.missingFunctionName
        )

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
    }
}
