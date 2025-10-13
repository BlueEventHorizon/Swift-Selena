//
//  ToolProtocol.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// MCPツールの共通プロトコル
///
/// 各ツールはこのプロトコルに準拠し、以下を提供する：
/// - toolDefinition: ListTools用のTool定義
/// - execute: CallTool用の実装
protocol MCPTool {
    /// ツール定義（ListToolsハンドラで使用）
    static var toolDefinition: Tool { get }

    /// ツール実行（CallToolハンドラで使用）
    /// - Parameters:
    ///   - params: CallToolパラメータ
    ///   - projectMemory: プロジェクトメモリ（未初期化の場合nil）
    ///   - logger: ロガー
    /// - Returns: ツール実行結果
    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result
}

/// ツール実装のヘルパー関数
enum ToolHelpers {
    /// ProjectMemory が初期化されているか確認
    static func requireProjectMemory(_ memory: ProjectMemory?) throws -> ProjectMemory {
        guard let memory = memory else {
            throw MCPError.invalidRequest(ErrorMessages.projectNotInitialized)
        }
        return memory
    }

    /// パラメータから文字列を取得
    static func getString(from args: [String: Value]?, key: String, errorMessage: String) throws -> String {
        guard let args = args,
              let value = args[key] else {
            throw MCPError.invalidParams(errorMessage)
        }
        return String(describing: value)
    }

    /// パラメータから整数を取得
    static func getInt(from args: [String: Value]?, key: String, defaultValue: Int) -> Int {
        guard let args = args,
              let value = args[key] else {
            return defaultValue
        }
        return Int(String(describing: value)) ?? defaultValue
    }

    /// パラメータからBoolを取得
    static func getBool(from args: [String: Value]?, key: String, defaultValue: Bool) -> Bool {
        guard let args = args,
              let value = args[key],
              case .bool(let boolValue) = value else {
            return defaultValue
        }
        return boolValue
    }
}
