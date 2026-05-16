//
//  Constants.swift
//  SwiftMCPServer
//
//  Created by k2moons on 2025/10/03.
//
//  [Code Header Format]
//
//  目的
//  - アプリ全体で共有する文字列・数値定数の一元管理
//  - MCP ツール名・パラメータキー・エラーメッセージの集約
//  - 検索系ツールの除外ディレクトリと応答上限値の定義
//
//  主要機能
//  - アプリ識別子・バージョン・ロガーラベル・保存先ディレクトリの提供
//  - ツール名・メタツール名・環境変数キー・パラメータキーの提供
//  - 入力検証エラー（cause / suggestion）の統一文言提供（DES-104 §8.1）
//  - 除外ディレクトリ判定 (ExcludedDirectories.shouldExclude)
//  - 構造化応答時の件数上限の提供（DES-104 §8.4）
//
//  含まれる型
//  - AppConstants: アプリ識別子・バージョン・保存先
//  - ToolNames: MCP ツール名
//  - MetaToolNames: メタツール名（v0.6.3 コード実行パターン）
//  - MetaParameterKeys: メタツール用パラメータキー
//  - EnvironmentKeys: 環境変数キー
//  - ParameterKeys: 各ツール共通のパラメータキー
//  - ExcludedDirectories: 検索系ツールの除外パス判定
//  - ErrorMessages: エラー文言（DES-104 §8.1 統一形式）
//  - ResponseLimits: 構造化応答の件数上限（DES-104 §8.4）
//

import Foundation

/// アプリケーション全体の定数
enum AppConstants {
    static let name = "Swift-Selena"
    static let version = "0.6.3"
    static let loggerLabel = "swift-selena"
    static let storageDirectory = ".swift-selena"
}

/// MCPツール名の定数
enum ToolNames {
    static let initializeProject = "initialize_project"
    static let findFiles = "find_files"
    static let searchCode = "search_code"
    static let searchFilesWithoutPattern = "search_files_without_pattern"
    static let listSymbols = "list_symbols"
    static let findSymbolDefinition = "find_symbol_definition"
    static let listPropertyWrappers = "list_property_wrappers"
    static let listProtocolConformances = "list_protocol_conformances"
    static let listExtensions = "list_extensions"
    static let analyzeImports = "analyze_imports"
    static let getTypeHierarchy = "get_type_hierarchy"
    static let findTestCases = "find_test_cases"
}

/// メタツール名の定数（v0.6.3: コード実行パターン）
enum MetaToolNames {
    static let listAvailableTools = "list_available_tools"
    static let getToolSchema = "get_tool_schema"
    static let executeTool = "execute_tool"
}

/// メタツール用パラメータキーの定数
enum MetaParameterKeys {
    static let toolName = "tool_name"
    static let params = "params"
}

/// 環境変数キーの定数
enum EnvironmentKeys {
    /// SWIFT_SELENA_LEGACY=1 で従来モード（全ツール公開）
    static let legacyMode = "SWIFT_SELENA_LEGACY"
}

/// パラメータキーの定数
enum ParameterKeys {
    static let projectPath = "project_path"
    static let filePath = "file_path"
    static let pattern = "pattern"
    static let symbolName = "symbol_name"
    static let typeName = "type_name"
    /// search_code の出力モード（"match_detail" / "file_list" / "count_only"）
    static let outputMode = "output_mode"
    /// 件数上限（1〜10,000）。search_code の結果件数制御に使用
    static let limit = "limit"
    /// 検索対象に含めるファイル glob 配列（search_code）
    static let includePatterns = "include_patterns"
    /// 検索対象から除外するファイル glob 配列（search_code）
    static let excludePatterns = "exclude_patterns"
    /// シンボル種別フィルタ配列（find_symbol_definition、小文字スネーク 9 区分）
    static let symbolKinds = "symbol_kinds"
}

/// 除外するディレクトリパターン（v0.5.4）
enum ExcludedDirectories {
    /// 除外するディレクトリ名
    static let patterns = [
        ".build",           // SwiftPM ビルド成果物
        "checkouts",        // SwiftPM 依存パッケージ
        "DerivedData",      // Xcode ビルドキャッシュ
        ".git",             // Git リポジトリ
        "Pods",             // CocoaPods 依存
        "Carthage",         // Carthage 依存
        ".swiftpm",         // SwiftPM 設定
        "xcuserdata"        // Xcode ユーザーデータ
    ]

    /// パスが除外対象か判定
    static func shouldExclude(_ path: String) -> Bool {
        return patterns.contains { path.contains("/\($0)/") || path.hasSuffix("/\($0)") }
    }
}

/// エラーメッセージの定数
enum ErrorMessages {
    static let projectNotInitialized = "Project not initialized"
    static let missingProjectPath = "Missing project_path"
    static let missingFilePath = "Missing file_path"
    static let missingPattern = "Missing pattern"
    static let missingSymbolName = "Missing symbol_name"
    static let missingTypeName = "Missing type_name"
    static let projectPathNotDirectory = "Project path does not exist or is not a directory"

    // MARK: - 入力検証エラー（DES-104 §8.1 統一形式の cause / suggestion）

    /// 正規表現構文エラーの cause 文言（pattern パラメータ不正）
    static let regexSyntaxErrorCause = "正規表現の構文が不正です。"
    /// 正規表現構文エラーの suggestion 文言
    static let regexSyntaxErrorSuggestion = "有効な正規表現を指定してください。例: \"func.*\\\\(\", \"^class\\\\s+\\\\w+\""

    /// glob 構文エラーの cause 文言（include_patterns / exclude_patterns 不正）
    static let globSyntaxErrorCause = "glob パターンの構文が不正です。"
    /// glob 構文エラーの suggestion 文言（DES-104 §8.1 固定文言）
    static let globSyntaxErrorSuggestion = "有効な glob パターン例: *.swift, Sources/**/*.swift, *Tests*"

    /// 件数上限の境界エラー cause 文言（0・負数・整数以外）
    static let limitBoundaryErrorCause = "件数上限 (limit) には 1 以上の整数を指定してください。"
    /// 件数上限の境界エラー suggestion 文言
    static let limitBoundaryErrorSuggestion = "limit は 1 以上 10000 以下の整数で指定してください。10000 を超える場合は内部上限に切り詰められます。"

    /// シンボル種別未定義エラーの cause 文言（symbol_kinds に未定義値が含まれる場合）
    static let symbolKindUndefinedCause = "未定義のシンボル種別が指定されています。"
    /// シンボル種別未定義エラーの suggestion 文言
    static let symbolKindUndefinedSuggestion = "次のいずれかを指定してください: struct, class, enum, protocol, actor, function, variable, typealias, extension"

    /// 配列要素数上限超過エラーの cause 文言（include_patterns / exclude_patterns / symbol_kinds）
    static let arrayCountExceededCause = "配列要素数が上限を超えています。"
    /// 配列要素数上限超過エラーの suggestion 文言
    static let arrayCountExceededSuggestion = "include_patterns / exclude_patterns は 20 件以下、symbol_kinds は 9 件以下で指定してください。"
}

/// 構造化結果出力に関する制限値（DES-104 §8.4）
enum ResponseLimits {
    /// 構造化結果の skipped_files フィールドに列挙する最大件数
    /// - Note: 上限超過時は skipped_files_truncated=true、total_skipped_count に上限適用前の総数を返す
    static let maxSkippedFilesInResponse = 100
}
