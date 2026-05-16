//
//  ToolProtocol.swift
//  Swift-Selena
//
//  Created by k2moons on 2025/10/13.
//
//  [Code Header Format]
//
//  目的
//  - MCPツール共通プロトコルの定義
//  - ツール実装で共通利用するパラメータ取得・検証ヘルパーの提供
//
//  主要機能
//  - ツール定義と実行の契約定義
//  - 文字列・整数・Bool・文字列配列・Optional 整数のパラメータ取得
//  - 配列要素数上限・型不正・null/省略の差異を区別したエラー応答
//
//  含まれる型
//  - MCPTool: 各 MCP ツールが準拠する共通プロトコル
//  - ToolHelpers: パラメータ取得・検証用ヘルパー関数群
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
              let value = args[key],
              case .string(let s) = value else {
            throw MCPError.invalidParams(errorMessage)
        }
        return s
    }

    /// パラメータから整数を取得
    static func getInt(from args: [String: Value]?, key: String, defaultValue: Int) -> Int {
        guard let args = args,
              let value = args[key] else {
            return defaultValue
        }
        // パターンマッチで型安全に値を取り出す
        switch value {
        case .int(let v):
            return v
        case .string(let s):
            // 文字列で渡された場合のフォールバック
            return Int(s) ?? defaultValue
        default:
            return defaultValue
        }
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

    /// パラメータから文字列配列を取得（DES-104 §4.3）
    ///
    /// 動作仕様:
    /// - フィールド省略・`.null` → 空配列 `[]` を返す（エラーにしない）
    /// - 空配列 `.array([])` → 空配列 `[]` を返す（エラーにしない）
    /// - `.array([.string(...), ...])` → 文字列を抽出して返す
    /// - `maxCount` を超える要素数 → `MCPError.invalidParams` をスロー
    /// - 配列要素に文字列以外が含まれる → `MCPError.invalidParams` をスロー
    /// - フィールドが配列以外の型で指定された → `MCPError.invalidParams` をスロー
    ///
    /// - Parameters:
    ///   - args: 引数辞書（`CallTool.Parameters.arguments`）
    ///   - key: 取得するパラメータキー
    ///   - maxCount: 許容する最大要素数（DES-104 §2 TBD-009 に従い呼び出し側が指定）
    /// - Returns: 抽出された文字列配列（省略・null・空配列時は空配列）
    static func getStringArray(
        from args: [String: Value]?,
        key: String,
        maxCount: Int
    ) throws -> [String] {
        // フィールド省略は未指定として空配列を返す
        guard let args = args, let value = args[key] else {
            return []
        }
        // 明示的な null も未指定として空配列を返す
        if case .null = value {
            return []
        }
        // 配列以外の型は入力エラー
        guard case .array(let items) = value else {
            throw MCPError.invalidParams(
                "Parameter '\(key)' must be an array of strings"
            )
        }
        // 空配列は未指定相当として空配列を返す（要件 §3.1 統一原則に準拠）
        if items.isEmpty {
            return []
        }
        // 要素数上限の検証（超過時は InvalidParams）
        if items.count > maxCount {
            throw MCPError.invalidParams(
                "Parameter '\(key)' exceeds maximum element count: \(items.count) > \(maxCount)"
            )
        }
        // 各要素を文字列として抽出。文字列以外が含まれる場合はエラー
        var result: [String] = []
        result.reserveCapacity(items.count)
        for (index, element) in items.enumerated() {
            guard case .string(let s) = element else {
                throw MCPError.invalidParams(
                    "Parameter '\(key)'[\(index)] must be a string"
                )
            }
            result.append(s)
        }
        return result
    }

    /// パラメータから Optional 整数を取得（DES-104 §4.3）
    ///
    /// 動作仕様:
    /// - フィールド省略・`.null` → `nil`（未指定として扱う）
    /// - `.int(v)` → `v`
    /// - `.string(s)` で Int に変換可能 → 変換後の値
    /// - フィールドは存在するが Int に変換できない型・文字列 → `MCPError.invalidParams` をスロー
    ///
    /// 設計意図: `getInt(from:key:defaultValue:)` は変換不能時にデフォルト値を返すが、
    /// 本ヘルパーは「省略（nil）」と「不正型入力（InvalidParams）」を明確に区別する。
    /// 件数上限のように「未指定＝無制限」と「不正値＝エラー」を分ける必要があるパラメータで使用する。
    ///
    /// - Parameters:
    ///   - args: 引数辞書（`CallTool.Parameters.arguments`）
    ///   - key: 取得するパラメータキー
    /// - Returns: 整数値、または未指定時は `nil`
    static func getOptionalInt(
        from args: [String: Value]?,
        key: String
    ) throws -> Int? {
        // フィールド省略は未指定として nil を返す
        guard let args = args, let value = args[key] else {
            return nil
        }
        // 明示的な null も未指定として nil を返す
        switch value {
        case .null:
            return nil
        case .int(let v):
            return v
        case .string(let s):
            // 文字列で渡された場合は Int に変換可能か検証する
            guard let parsed = Int(s) else {
                throw MCPError.invalidParams(
                    "Parameter '\(key)' must be an integer (got non-integer string: '\(s)')"
                )
            }
            return parsed
        default:
            // 配列・オブジェクト・Bool・Double 等は不正型として明示的に拒否
            throw MCPError.invalidParams(
                "Parameter '\(key)' must be an integer"
            )
        }
    }
}
