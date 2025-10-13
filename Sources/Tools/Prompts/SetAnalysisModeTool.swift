//
//  SetAnalysisModeTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// 分析モード設定ツール
///
/// ## 目的
/// 分析タスクに応じた最適なツール使用順序と分析観点をガイド
///
/// ## 効果
/// - ユーザーの指示が簡潔になる（「SwiftUIモードで分析」だけでOK）
/// - Claudeが最適な手順で分析を実行
/// - 分析の抜け漏れを防止
/// - タスクに応じた推奨ツールを提示
///
/// ## 提供モード
/// - **swiftui**: SwiftUIアプリの分析（Property Wrapper、State管理）
/// - **architecture**: アーキテクチャ分析（レイヤー分離、依存関係）
/// - **testing**: テストカバレッジ分析
/// - **refactoring**: リファクタリング候補の検出
/// - **general**: 一般的な分析
///
/// ## 使用例
/// set_analysis_mode(mode: "swiftui")
/// → SwiftUI分析の推奨手順とチェックポイントを返す
///
/// ## 参考
/// Serenaのモード機能を参考に実装
enum SetAnalysisModeTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.setAnalysisMode,
            description: "Set analysis mode and get guidance for optimal tool usage",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    ParameterKeys.mode: .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("general"),
                            .string("swiftui"),
                            .string("architecture"),
                            .string("testing"),
                            .string("refactoring")
                        ]),
                        "description": .string("Analysis mode to activate")
                    ])
                ]),
                "required": .array([.string(ParameterKeys.mode)])
            ])
        )
    }

    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result {
        guard let args = params.arguments,
              let modeValue = args[ParameterKeys.mode],
              case .string(let mode) = modeValue else {
            throw MCPError.invalidParams(ErrorMessages.missingMode)
        }

        let guidance = switch mode {
        case "swiftui":
            """
            ✅ SwiftUI分析モードを設定しました

            ## 推奨ツール順序
            1. find_files("*View.swift", "*ViewModel.swift") - View/ViewModelファイルを検索
            2. list_property_wrappers - State管理パターンを把握
            3. list_protocol_conformances - ObservableObject等を確認
            4. get_type_hierarchy - ViewModel階層を理解

            ## 分析観点
            - @State, @ObservedObject, @EnvironmentObject の使用パターン
            - データバインディングの設計
            - View階層の複雑さ
            - MVVM準拠度

            ## レポート推奨項目
            - State管理の一貫性
            - データフローの明確さ
            - パフォーマンス上の懸念（過度な@State等）
            """

        case "architecture":
            """
            ✅ アーキテクチャ分析モードを設定しました

            ## 推奨ツール順序
            1. analyze_imports - モジュール依存関係
            2. get_type_hierarchy - 主要な型の階層
            3. list_protocol_conformances - Protocol設計
            4. find_type_usages - 型の使用パターン

            ## 分析観点
            - レイヤー分離（Model/View/ViewModel）
            - 依存性の方向性
            - Protocol Oriented Programming
            - SOLID原則への準拠

            ## mermaid図の生成推奨
            - モジュール依存グラフ
            - 型階層図
            - データフロー図
            """

        case "testing":
            """
            ✅ テスト分析モードを設定しました

            ## 推奨ツール順序
            1. find_test_cases - テストケース一覧
            2. find_files("*.swift") - 全Swiftファイル取得
            3. 各テスト対象についてテストの有無を確認

            ## 分析観点
            - テストカバレッジ（推定）
            - テストが不足しているクラス/関数
            - テストの命名規則
            - XCTest vs Swift Testing

            ## レポート推奨項目
            - カバレッジ推定値
            - 優先的にテストすべき箇所
            - テストしやすさの評価
            """

        case "refactoring":
            """
            ✅ リファクタリング分析モードを設定しました

            ## 推奨ツール順序
            1. find_files - ファイル一覧
            2. list_symbols - 各ファイルのシンボル数確認
            3. search_code - 重複パターンの検索
            4. get_type_hierarchy - 継承の深さ確認

            ## 分析観点
            - 巨大なファイル（>500行）の検出
            - 巨大なクラス（>20メソッド）の検出
            - 重複コードの検出
            - 循環依存の検出

            ## 提案フォーマット
            問題点 → 具体的な改善案 → 優先度
            """

        case "general":
            """
            ✅ 一般分析モードを設定しました

            ## 利用可能なツール
            - ファイル検索: find_files, search_code
            - シンボル解析: list_symbols, find_symbol_definition
            - 依存関係: analyze_imports, get_type_hierarchy
            - SwiftUI特化: list_property_wrappers, list_protocol_conformances
            - テスト: find_test_cases

            ## ヒント
            - 特定の目的がある場合は、専用モードの使用を推奨
            - swiftui / architecture / testing / refactoring
            """

        default:
            throw MCPError.invalidParams(ErrorMessages.invalidMode)
        }

        return CallTool.Result(content: [.text(guidance)])
    }
}
