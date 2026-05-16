//
//  CapabilityRegistry.swift
//  Swift-Selena
//
//  Created by k2moons on 2026/05/16.
//
//  [Code Header Format]
//
//  目的
//  - REQ-005 §4.7.1 ケーパビリティ通知の最小実装
//  - ListTools / list_available_tools 応答時点で「動作可能なツール一覧」を提供
//
//  主要機能
//  - 現環境で利用可能なツール名一覧の返却（無条件で全ツール）
//  - MetaToolRegistry をラップするのみで、前提条件チェック・並列実行・タイムアウト・キャンセル協調・状態機械は持たない
//

import Foundation

/// 利用可能ツール一覧を提供するレジストリ（最小実装）
///
/// ## 設計方針（DES-104 §7.2 / v2.0 簡素化）
///
/// REQ-005 §4.7.1 が要求するのは「ListTools 応答時点で動作可能なツールのみを返す」ことのみ。
/// 本 Feature 対象のツール（`search_code` / `find_symbol_definition` / `list_symbols` 等）は
/// すべて前提条件なし（常に動作可能）であるため、最小実装で十分である。
///
/// 将来、LSP 系ツール等の前提条件を持つツールを追加する際は、
/// `availableTools()` 内に条件分岐を追加する。
///
/// - Important: 本実装は `actor` ではなく `enum` + `static func` のみで構成する。
///   並列前提条件チェック・タイムアウト戦略・キャンセル協調・状態機械等の複雑な
///   インフラ整備は本 Feature では導入しない（DES-104 v2.0 簡素化方針）。
enum CapabilityRegistry {

    /// 現環境で動作可能なツール名の一覧を返す
    ///
    /// 本 Feature の対象ツールはすべて無条件で利用可能なため、
    /// `MetaToolRegistry` が把握する全ツール（`initialize_project` を含む 12 種類）を
    /// そのまま返す。
    ///
    /// 将来、前提条件を持つツール（LSP 系等）を追加する際は、
    /// 本メソッド内に条件分岐を追加して動作不可能なツールを除外する。
    ///
    /// - Returns: 利用可能ツール名の配列（`MetaToolRegistry.getToolDefinition` で
    ///   `Tool` 定義を取得する際のキーとして使用される）
    static func availableTools() -> [String] {
        // initialize_project は MetaToolRegistry.toolSummaries に含まれないため、
        // 先頭に明示的に追加する（ListTools legacy モードの 12 ツール構成と整合）。
        return [ToolNames.initializeProject] + MetaToolRegistry.allToolNames
    }
}
