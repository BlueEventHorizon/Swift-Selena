//
//  SymbolKindMapper.swift
//  Swift-Selena
//
//  Created by k2moons on 2026/05/10.
//
//  [Code Header Format]
//
//  目的
//  - find_symbol_definition の symbol_kinds（小文字スネーク）と Visitor 表示用 kind の対応付け
//  - 未定義種別の入力検証と優先返却グループ分類（DES-104 §6.2）
//
//  主要機能
//  - 利用者指定値と表示用 kind の双方向変換（TBD-005 対応表）
//  - symbol_kinds 配列の検証（未定義値は InvalidParams）
//  - 表示用 kind から優先返却グループ（0/1/2）への分類
//  - 定義済み 9 区分の利用者指定値一覧の公開
//

import Foundation
import MCP

/// `symbol_kinds` パラメータと `SymbolVisitor` / `SymbolVisitorV2` の表示用 kind を橋渡しする（DES-104 §4.2）
enum SymbolKindMapper {
    /// 利用者指定値（小文字スネーク）と表示用 kind の対応（TBD-005・単一情報源）
    private static let mapping: [(userInput: String, displayKind: String)] = [
        ("struct", "Struct"),
        ("class", "Class"),
        ("enum", "Enum"),
        ("protocol", "Protocol"),
        ("actor", "Actor"),
        ("function", "Function"),
        ("variable", "Variable"),
        ("typealias", "TypeAlias"),
        ("extension", "Extension")
    ]

    private static let userInputToDisplayDict: [String: String] = {
        Dictionary(uniqueKeysWithValues: mapping.map { ($0.userInput, $0.displayKind) })
    }()

    private static let displayKindToUserDict: [String: String] = {
        Dictionary(uniqueKeysWithValues: mapping.map { ($0.displayKind, $0.userInput) })
    }()

    /// 定義済み 9 区分の利用者指定値一覧（安定した並び。エラーメッセージ生成等から参照可能）
    static let validUserInputs: [String] = mapping.map(\.userInput)

    /// 小文字スネークの利用者指定値を表示用 kind に変換する。マッピング外は `nil`
    static func userInputToDisplayKind(_ input: String) -> String? {
        userInputToDisplayDict[input]
    }

    /// 表示用 kind を小文字スネークの利用者指定値に変換する。マッピング外は `nil`
    static func displayKindToUserInput(_ kind: String) -> String? {
        displayKindToUserDict[kind]
    }

    /// `symbol_kinds` に未定義の種別が 1 件でも含まれる場合は `MCPError.invalidParams` をスローする
    ///
    /// - Note: エラーメッセージには無効な値を列挙する（重複は除き、昇順で並べる）
    static func validate(_ inputs: [String]) throws {
        let invalid = inputs.filter { userInputToDisplayDict[$0] == nil }
        guard !invalid.isEmpty else { return }

        let uniqueSorted = Array(Set(invalid)).sorted()
        let enumeratedInvalid = uniqueSorted.joined(separator: ", ")
        let message = """
        \(ErrorMessages.symbolKindUndefinedCause)
        無効な値: \(enumeratedInvalid)
        \(ErrorMessages.symbolKindUndefinedSuggestion)
        """
        throw MCPError.invalidParams(message)
    }

    /// 優先返却グループ（DES-104 §6.2）
    /// - `0`: 優先返却対象（Class / Struct / Enum / Protocol / Actor）
    /// - `1`: 非優先返却対象（Function / Variable / TypeAlias / Extension）
    /// - `2`: 対象外（Macro など上記以外の表示用 kind）
    static func priorityGroup(_ displayKind: String) -> Int {
        switch displayKind {
        case "Class", "Struct", "Enum", "Protocol", "Actor":
            return 0
        case "Function", "Variable", "TypeAlias", "Extension":
            return 1
        default:
            return 2
        }
    }
}
