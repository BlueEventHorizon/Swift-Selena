//
//  GetTypeHierarchyTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// 型階層取得ツール
///
/// ## 目的
/// 指定した型の継承階層とProtocol準拠関係を完全に把握
///
/// ## 効果
/// - スーパークラスの取得（継承元クラス）
/// - サブクラスの列挙（継承先クラス）
/// - Protocol準拠リストの取得
/// - Protocolを実装している型の列挙
/// - 型の依存関係を視覚的に理解
///
/// ## 処理内容
/// - プロジェクト内の全型情報をキャッシュから取得
/// - 指定された型を起点に階層構造を構築
/// - 継承関係を上下双方向に探索
/// - Protocol準拠関係も同時に収集
/// - キャッシュを利用して高速化
///
/// ## 使用シーン
/// - クラス階層を理解したい時
/// - リファクタリングの影響範囲を確認したい時
/// - Protocol実装状況を調査したい時
/// - アーキテクチャの理解を深めたい時
///
/// ## 使用例
/// get_type_hierarchy(type_name: "ViewController")
/// → Type Hierarchy for 'ViewController':
///   [Class] ViewController
///     Location: ViewController.swift:15
///   Inherits from:
///     └─ UIViewController
///   Conforms to:
///     └─ UITableViewDelegate
///     └─ UITableViewDataSource
///   Subclasses:
///     └─ UserViewController
///     └─ SettingsViewController
///
///
/// ## パフォーマンス（全ファイル処理する場合）
/// - 340ファイルのプロジェクトで初回約3-5秒
/// - 2回目以降はキャッシュにより約0.5秒
enum GetTypeHierarchyTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.getTypeHierarchy,
            description: "Get the inheritance hierarchy for a specific type",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "type_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the type to analyze")
                    ])
                ]),
                "required": .array([.string("type_name")])
            ])
        )
    }

    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result {
        let memory = try ToolHelpers.requireProjectMemory(projectMemory)
        let typeName = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.typeName,
            errorMessage: ErrorMessages.missingTypeName
        )

        guard let hierarchy = try SwiftSyntaxAnalyzer.getTypeHierarchy(
            typeName: typeName,
            projectPath: memory.projectPath,
            projectMemory: memory
        ) else {
            return CallTool.Result(content: [.text("Type '\(typeName)' not found in project")])
        }

        var result = "Type Hierarchy for '\(typeName)':\n\n"
        result += "[\(hierarchy.typeKind)] \(hierarchy.typeName)\n"
        result += "  Location: \(hierarchy.filePath):\(hierarchy.line)\n\n"

        if let superclass = hierarchy.superclass {
            result += "Inherits from:\n"
            result += "  └─ \(superclass)\n\n"
        }

        if !hierarchy.protocols.isEmpty {
            result += "Conforms to:\n"
            for proto in hierarchy.protocols {
                result += "  └─ \(proto)\n"
            }
            result += "\n"
        }

        if !hierarchy.subclasses.isEmpty {
            result += "Subclasses:\n"
            for subclass in hierarchy.subclasses {
                result += "  └─ \(subclass)\n"
            }
            result += "\n"
        }

        if !hierarchy.conformingTypes.isEmpty {
            result += "Types conforming to this protocol:\n"
            for type in hierarchy.conformingTypes {
                result += "  └─ \(type)\n"
            }
            result += "\n"
        }

        return CallTool.Result(content: [.text(result)])
    }
}
