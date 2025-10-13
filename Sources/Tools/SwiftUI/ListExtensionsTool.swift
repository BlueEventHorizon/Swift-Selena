//
//  ListExtensionsTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// Extension一覧ツール
///
/// ## 目的
/// ファイル内のExtension定義とそのメンバーを全て列挙
///
/// ## 効果
/// - Extension対象の型を把握
/// - Extensionで追加されたProtocol準拠を確認
/// - Extensionのメンバー（メソッド、プロパティ）を列挙
/// - コードの構造を理解
///
/// ## 処理内容
/// - SwiftSyntaxでExtensionDeclノードを検出
/// - 拡張対象の型名を抽出
/// - Protocol準拠リストを取得
/// - Extension内のメンバー（関数、変数など）を列挙
/// - 各メンバーの種類と行番号を記録
///
/// ## 使用シーン
/// - Protocol準拠がどこで実装されているか調査
/// - 型の機能拡張を把握したい時
/// - Extension分割の構造を理解したい時
/// - リファクタリングでExtensionを整理する時
///
/// ## 使用例
/// list_extensions(file_path: "ViewController.swift")
/// → Extensions in ViewController.swift:
///   [Extension] ViewController (line 50)
///     Conforms to: UITableViewDelegate, UITableViewDataSource
///     Members:
///       [Function] numberOfSections (line 52)
///       [Function] tableView(_:numberOfRowsInSection:) (line 56)
///
enum ListExtensionsTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.listExtensions,
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
    }
}
