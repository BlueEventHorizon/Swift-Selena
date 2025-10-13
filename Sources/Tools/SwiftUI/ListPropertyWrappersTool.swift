//
//  ListPropertyWrappersTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// Property Wrapper一覧ツール
///
/// ## 目的
/// SwiftUIのProperty Wrapper（@State、@Bindingなど）を解析
///
/// ## 効果
/// - @State、@Binding、@ObservedObject、@StateObjectなどを検出
/// - プロパティ名と型情報を取得
/// - SwiftUIの状態管理構造を理解
/// - データフローを可視化
///
/// ## 処理内容
/// - SwiftSyntaxでAttributeノードを検出
/// - Property Wrapperの種類を識別（@State、@Bindingなど）
/// - 対応するプロパティの名前を取得
/// - プロパティの型注釈を抽出
/// - 行番号を記録
///
/// ## 使用シーン
/// - SwiftUIビューの状態管理を理解したい時
/// - データフローを追跡したい時
/// - @Bindingの受け渡しを確認したい時
/// - リファクタリングで状態管理を見直す時
///
/// ## 使用例
/// list_property_wrappers(file_path: "ContentView.swift")
/// → Property Wrappers in ContentView.swift:
///   [@State] counter: Int (line 12)
///   [@Binding] isPresented: Bool (line 13)
///   [@ObservedObject] viewModel: ViewModel (line 14)
///
enum ListPropertyWrappersTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.listPropertyWrappers,
            description: "List SwiftUI property wrappers (@State, @Binding, etc.) in a file",
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

        let wrappers = try SwiftSyntaxAnalyzer.listPropertyWrappers(filePath: filePath)

        if wrappers.isEmpty {
            return CallTool.Result(content: [.text("No property wrappers found in \(filePath)")])
        }

        var result = "Property Wrappers in \(filePath):\n\n"
        for wrapper in wrappers {
            result += "[@\(wrapper.wrapperType)] \(wrapper.propertyName)"
            if let typeName = wrapper.typeName {
                result += ": \(typeName)"
            }
            result += " (line \(wrapper.line))\n"
        }

        return CallTool.Result(content: [.text(result)])
    }
}
