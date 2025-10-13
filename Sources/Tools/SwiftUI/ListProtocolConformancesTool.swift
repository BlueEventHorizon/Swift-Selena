//
//  ListProtocolConformancesTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// Protocol準拠一覧ツール
///
/// ## 目的
/// ファイル内の型のProtocol準拠と継承関係を一覧表示
///
/// ## 効果
/// - Class、Struct、EnumのProtocol準拠を把握
/// - クラス継承関係を確認
/// - 型の種類（Class/Struct/Enum/Protocol）を識別
/// - アーキテクチャパターンの理解を支援
///
/// ## 処理内容
/// - SwiftSyntaxでClass/Struct/Enum宣言を検出
/// - InheritanceClauseからスーパークラスとProtocolを抽出
/// - 型の種類を判定
/// - 各型の行番号を記録
///
/// ## 使用シーン
/// - UITableViewDelegateなどのProtocol実装を探す時
/// - 型のアーキテクチャ役割を理解したい時
/// - Protocol Oriented Programmingの構造を把握
/// - リファクタリングでProtocol設計を見直す時
///
/// ## 使用例
/// list_protocol_conformances(file_path: "ViewController.swift")
/// → Protocol Conformances in ViewController.swift:
///   [Class] ViewController (line 10)
///     Inherits from: UIViewController
///     Conforms to: UITableViewDelegate, UITableViewDataSource
///
///   [Struct] UserViewModel (line 80)
///     Conforms to: ObservableObject, Identifiable
///
enum ListProtocolConformancesTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.listProtocolConformances,
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
    }
}
