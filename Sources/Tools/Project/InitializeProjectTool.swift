//
//  InitializeProjectTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// プロジェクト初期化ツール
///
/// ## 目的
/// Swiftプロジェクトの解析を開始するための初期化を行います。全てのツールの前提条件です。
///
/// ## 効果
/// - ProjectMemoryインスタンスを作成
/// - プロジェクトパスを記録
/// - メモリキャッシュシステムを起動
/// - 永続化ディレクトリを準備
///
/// ## 処理内容
/// - プロジェクトパスの存在確認
/// - プロジェクトパスのハッシュ計算（SHA256の先頭8文字）
/// - `~/.swift-selena/clients/{clientId}/projects/{projectName}-{hash}/`にディレクトリ作成
/// - memory.jsonが存在すれば読み込み（既存プロジェクトの場合）
/// - 新規プロジェクトなら空のメモリを初期化
///
/// ## 使用シーン
/// - セッション開始時に必ず最初に呼び出す
/// - プロジェクトを切り替える時
/// - 新しいプロジェクトの解析を始める時
///
/// ## 使用例
/// initialize_project(project_path: "/path/to/swift/project")
/// → ✅ Project initialized: /path/to/swift/project
///   Project Statistics:
///   Path: /path/to/swift/project
///   Indexed files: 0 (初回), 340 (2回目以降)
///   Cached symbols: 0 (初回), 1,250 (2回目以降)
///
///
/// ## 重要な注意
/// - このツールは必ず最初に実行する必要があります
/// - 他の全てのツールはこのツールで初期化されたProjectMemoryに依存します
/// - 実行しないと他のツールは「Project not initialized」エラーになります
///
/// ## 注意: このツールはprojectMemoryを変更するため、
/// SwiftMCPServer.swiftで特別に処理される
enum InitializeProjectTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.initializeProject,
            description: "Initialize a Swift project for analysis. Must be called first.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    ParameterKeys.projectPath: .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to Swift project root")
                    ])
                ]),
                "required": .array([.string(ParameterKeys.projectPath)])
            ])
        )
    }

    /// プロジェクトを初期化
    ///
    /// - Returns: (結果メッセージ, 初期化されたProjectMemory)
    static func execute(
        params: CallTool.Parameters,
        logger: Logger
    ) async throws -> (result: CallTool.Result, memory: ProjectMemory) {
        let projectPath = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.projectPath,
            errorMessage: ErrorMessages.missingProjectPath
        )

        // プロジェクトパスの存在確認
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw MCPError.invalidParams(ErrorMessages.projectPathNotDirectory)
        }

        let memory = try ProjectMemory(projectPath: projectPath)

        #if DEBUG
        let message = "✅ Project initialized: \(projectPath)\n\n\(memory.getStats())"
        #else
        let message = "✅ Project initialized: \(projectPath)"
        #endif
        let result = CallTool.Result(content: [.text(message)])

        return (result, memory)
    }
}
