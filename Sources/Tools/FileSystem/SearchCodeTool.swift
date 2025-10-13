//
//  SearchCodeTool.swift
//  Swift-Selena
//
//  Created on 2025/10/13.
//

import Foundation
import MCP
import Logging

/// コード検索ツール（grep風）
///
/// ## 目的
/// 正規表現パターンを使用してコード内容を検索
///
/// ## 効果
/// - grep風の強力な正規表現検索
/// - 関数、変数、コメントなど任意のコードパターンを発見
/// - マッチした行番号とコンテキストを表示
/// - オプションでファイルパターンによる絞り込みが可能
///
/// ## 処理内容
/// - プロジェクト内のファイルを走査（オプションでfilePatternで絞り込み）
/// - 各ファイルの内容を正規表現でマッチング
/// - マッチした行の内容、ファイルパス、行番号を記録
/// - .git、.buildなどの不要なディレクトリは自動スキップ
///
/// ## 使用シーン
/// - 特定のAPIやメソッド呼び出し箇所を探す時
/// - TODOコメントやFIXMEを検索する時
/// - 非推奨APIの使用箇所を洗い出す時
/// - コーディング規約違反を検出する時
///
/// ## 使用例
/// search_code(pattern: "func.*\\(", file_pattern: "*.swift")
/// → Found 127 matches:
///   UserManager.swift:15: func createUser(name: String) {
///   AuthService.swift:42: func login(email: String, password: String) {
///
///
/// ## find_filesとの違い
/// - find_files: ファイル名で検索（ファイルシステム走査）
/// - search_code: ファイル内容で検索（テキスト検索）
///
/// ## パフォーマンス（全ファイル処理する場合）
/// - 340ファイルのプロジェクトで約1-2秒
/// - 正規表現の複雑さにより変動
enum SearchCodeTool: MCPTool {
    static var toolDefinition: Tool {
        Tool(
            name: ToolNames.searchCode,
            description: "Search code content using regex pattern (grep-like search)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    ParameterKeys.pattern: .object([
                        "type": .string("string"),
                        "description": .string("Regex pattern to search for")
                    ]),
                    ParameterKeys.filePattern: .object([
                        "type": .string("string"),
                        "description": .string("Optional file pattern to limit search (e.g., '*.swift')")
                    ])
                ]),
                "required": .array([.string(ParameterKeys.pattern)])
            ])
        )
    }

    static func execute(
        params: CallTool.Parameters,
        projectMemory: ProjectMemory?,
        logger: Logger
    ) async throws -> CallTool.Result {
        let memory = try ToolHelpers.requireProjectMemory(projectMemory)
        let pattern = try ToolHelpers.getString(
            from: params.arguments,
            key: ParameterKeys.pattern,
            errorMessage: ErrorMessages.missingPattern
        )
        let filePattern = params.arguments?[ParameterKeys.filePattern].map { String(describing: $0) }

        let matches = try FileSearcher.searchCode(
            in: memory.projectPath,
            pattern: pattern,
            filePattern: filePattern
        )

        var result = "Found \(matches.count) matches:\n\n"
        for match in matches {
            result += "\(match.file):\(match.line): \(match.content.trimmingCharacters(in: .whitespaces))\n"
        }

        return CallTool.Result(content: [.text(result)])
    }
}
