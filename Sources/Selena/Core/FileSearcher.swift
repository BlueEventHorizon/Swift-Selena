//
//  FileSearcher.swift
//  SwiftMCPServer
//
//  Created by k2moons on 2025/10/03.
//
//  [Code Header Format]
//
//  目的
//  - プロジェクト配下のファイル探索とコード内容の正規表現検索
//  - glob（単一 *・**）によるパスフィルタと include/exclude の評価
//  - 検索結果の出力モード別整形データの提供（DES-104 §4.4）
//
//  主要機能
//  - ワイルドカードによるファイル名検索と結果パスのソート返却
//  - コード検索の複数 glob・件数上限・出力モード対応
//  - ディレクトリ列挙失敗時の明示的エラー通知（DES-104 §8.5）
//
//  含まれる型
//  - SearchOutputMode, Match, SearchCodeResult（DES-104 §4.4）
//

import Foundation

/// コード検索の出力モード（DES-104 §4.4）
enum SearchOutputMode {
    /// ファイル・行番号・マッチ行を返す（既定）
    case matchDetail
    /// マッチを含むファイル一覧（重複排除）
    case fileList
    /// マッチ数・ファイル数のみ（件数上限は適用しない／DES-104 §5.1）
    case countOnly
}

/// 1 件のマッチ行（DES-104 §4.4）
struct Match: Sendable {
    /// マッチしたファイルの絶対パス
    let file: String
    /// マッチした行番号（1 始まり）
    let line: Int
    /// マッチ行のテキスト
    let content: String
}

/// `searchCode` の構造化結果（DES-104 §4.4）
struct SearchCodeResult: Sendable {
    /// `matchDetail` 時のマッチ一覧（上限適用後）
    let matches: [Match]
    /// `fileList` 時のファイルパス一覧（重複排除・上限適用後）
    let files: [String]
    /// 件数上限適用前の総マッチ数
    let totalMatchCount: Int
    /// 件数上限適用前のマッチを含むファイル数（重複排除）
    let totalFileCount: Int
    /// 利用者指定の件数上限により結果が切り詰められた場合 true
    let truncated: Bool
    /// 内部上限（10000）へ切り詰めた場合 true（DES-104 TBD-010）
    let truncatedToMaxLimit: Bool
}

/// ファイルシステムベースの検索機能
enum FileSearcher {
    /// 内部での件数上限の上限（DES-104 TBD-010）
    private static let maxMatchLimit = 10_000

    /// `**` を単独の `*` と区別するためのプライベート用途 Unicode（DES-104 §4.4）
    private static let doubleStarPlaceholder: Character = "\u{E000}"

    // MARK: - Public API

    /// ワイルドカードパターンでファイルを検索
    static func findFiles(in directory: String, pattern: String) throws -> [String] {
        var results: [String] = []
        let fileManager = FileManager.default

        let regex = try NSRegularExpression(
            pattern: wildcardToRegex(pattern),
            options: [.caseInsensitive]
        )

        let enumerator = try directoryEnumerator(at: directory, fileManager: fileManager)

        for case let file as String in enumerator {
            // 除外ディレクトリをスキップ（v0.5.4: Constants使用）
            let fullPath = (directory as NSString).appendingPathComponent(file)
            if ExcludedDirectories.shouldExclude(fullPath) {
                continue
            }

            if file.hasSuffix(".swift") {
                // ファイル名部分だけを取り出してマッチング
                let fileName = (file as NSString).lastPathComponent
                let range = NSRange(fileName.startIndex..., in: fileName)
                if regex.firstMatch(in: fileName, range: range) != nil {
                    results.append((directory as NSString).appendingPathComponent(file))
                }
            }
        }

        return results.sorted()
    }

    /// 正規表現でコード内容を検索（grep的検索）
    /// 後方互換のため残し、拡張シグネチャへ委譲する。
    static func searchCode(in directory: String, pattern: String, filePattern: String?) throws -> [(file: String, line: Int, content: String)] {
        let includePatterns: [String]
        if let filePattern {
            includePatterns = [filePattern]
        } else {
            includePatterns = []
        }
        let result = try searchCode(
            in: directory,
            pattern: pattern,
            includePatterns: includePatterns,
            excludePatterns: [],
            limit: nil,
            outputMode: .matchDetail
        )
        return result.matches.map { ($0.file, $0.line, $0.content) }
    }

    /// 正規表現でコード内容を検索（include/exclude・上限・出力モード対応／DES-104 §4.4）
    static func searchCode(
        in directory: String,
        pattern: String,
        includePatterns: [String],
        excludePatterns: [String],
        limit: Int?,
        outputMode: SearchOutputMode
    ) throws -> SearchCodeResult {
        let regex = try NSRegularExpression(pattern: pattern, options: [])

        let includeRegexes: [NSRegularExpression]
        if includePatterns.isEmpty {
            includeRegexes = []
        } else {
            includeRegexes = try compiledGlobRegexes(patterns: includePatterns)
        }

        let excludeRegexes: [NSRegularExpression]
        if excludePatterns.isEmpty {
            excludeRegexes = []
        } else {
            excludeRegexes = try compiledGlobRegexes(patterns: excludePatterns)
        }

        let fileManager = FileManager.default
        let enumerator = try directoryEnumerator(at: directory, fileManager: fileManager)

        var allMatches: [Match] = []

        for case let file as String in enumerator {
            let fullPath = (directory as NSString).appendingPathComponent(file)
            if ExcludedDirectories.shouldExclude(fullPath) {
                continue
            }

            guard shouldSearchFile(
                relativePath: file,
                includePatterns: includePatterns,
                excludePatterns: excludePatterns,
                includeRegexes: includeRegexes,
                excludeRegexes: excludeRegexes
            ) else {
                continue
            }

            if let content = try? String(contentsOfFile: fullPath) {
                let lines = content.components(separatedBy: .newlines)
                for (lineNumber, lineContent) in lines.enumerated() {
                    let range = NSRange(lineContent.startIndex..., in: lineContent)
                    if regex.firstMatch(in: lineContent, range: range) != nil {
                        allMatches.append(Match(file: fullPath, line: lineNumber + 1, content: lineContent))
                    }
                }
            }
        }

        let totalMatchCount = allMatches.count
        let uniqueFilePaths = Set(allMatches.map(\.file))
        let totalFileCount = uniqueFilePaths.count

        // count_only では limit が結果に適用されない（DES-104 §5.1）ため上限クリップ通知も不要
        var truncatedToMaxLimit = false
        var effectiveLimit: Int?
        if outputMode != .countOnly, let lim = limit {
            if lim > maxMatchLimit {
                effectiveLimit = maxMatchLimit
                truncatedToMaxLimit = true
            } else {
                effectiveLimit = lim
            }
        }

        switch outputMode {
        case .matchDetail:
            let cappedMatches: [Match]
            let truncated: Bool
            if let lim = effectiveLimit {
                cappedMatches = Array(allMatches.prefix(lim))
                truncated = totalMatchCount > cappedMatches.count
            } else {
                cappedMatches = allMatches
                truncated = false
            }
            return SearchCodeResult(
                matches: cappedMatches,
                files: [],
                totalMatchCount: totalMatchCount,
                totalFileCount: totalFileCount,
                truncated: truncated,
                truncatedToMaxLimit: truncatedToMaxLimit
            )

        case .fileList:
            let sortedUniqueFiles = uniqueFilePaths.sorted()
            let cappedFiles: [String]
            let truncated: Bool
            if let lim = effectiveLimit {
                cappedFiles = Array(sortedUniqueFiles.prefix(lim))
                truncated = sortedUniqueFiles.count > cappedFiles.count
            } else {
                cappedFiles = sortedUniqueFiles
                truncated = false
            }
            return SearchCodeResult(
                matches: [],
                files: cappedFiles,
                totalMatchCount: totalMatchCount,
                totalFileCount: totalFileCount,
                truncated: truncated,
                truncatedToMaxLimit: truncatedToMaxLimit
            )

        case .countOnly:
            return SearchCodeResult(
                matches: [],
                files: [],
                totalMatchCount: totalMatchCount,
                totalFileCount: totalFileCount,
                truncated: false,
                truncatedToMaxLimit: false
            )
        }
    }

    /// パターンにマッチしないファイルを検索（grep -L相当）
    static func searchFilesWithoutPattern(
        in directory: String,
        pattern: String,
        filePattern: String?
    ) throws -> (filesWithoutPattern: [String], totalChecked: Int) {
        var filesWithoutPattern: [String] = []
        var totalChecked = 0
        let fileManager = FileManager.default

        // マルチラインモード（^と$が各行の先頭・末尾にマッチ）
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])

        let enumerator = try directoryEnumerator(at: directory, fileManager: fileManager)

        for case let file as String in enumerator {
            // 除外ディレクトリをスキップ
            let fullPath = (directory as NSString).appendingPathComponent(file)
            if ExcludedDirectories.shouldExclude(fullPath) {
                continue
            }

            let shouldSearch: Bool
            if let filePattern {
                let fileRegex = try NSRegularExpression(
                    pattern: wildcardToRegex(filePattern),
                    options: [.caseInsensitive]
                )
                let range = NSRange(file.startIndex..., in: file)
                shouldSearch = fileRegex.firstMatch(in: file, range: range) != nil
            } else {
                shouldSearch = file.hasSuffix(".swift")
            }

            if shouldSearch {
                totalChecked += 1
                // ファイル全体を読み込んでパターンマッチング
                if let content = try? String(contentsOfFile: fullPath) {
                    let range = NSRange(content.startIndex..., in: content)
                    let hasMatch = regex.firstMatch(in: content, range: range) != nil

                    // マッチしないファイルを収集
                    if !hasMatch {
                        filesWithoutPattern.append(fullPath)
                    }
                }
            }
        }

        return (filesWithoutPattern: filesWithoutPattern.sorted(), totalChecked: totalChecked)
    }

    /// ワイルドカードパターンを正規表現に変換（単一 `*`・`?`・`.` に加え `**` を再帰パス一致として扱う）
    internal static func wildcardToRegex(_ pattern: String) -> String {
        var withPlaceholders = ""
        let chars = Array(pattern)
        var idx = 0
        while idx < chars.count {
            if idx + 1 < chars.count, chars[idx] == "*", chars[idx + 1] == "*" {
                withPlaceholders.append(doubleStarPlaceholder)
                idx += 2
                continue
            }
            withPlaceholders.append(chars[idx])
            idx += 1
        }

        var result = "^"
        for char in withPlaceholders {
            if char == doubleStarPlaceholder {
                result += ".*"
                continue
            }
            switch char {
            case "*":
                result += ".*"
            case "?":
                result += "."
            case ".":
                result += "\\."
            default:
                result += String(char)
            }
        }
        result += "$"
        return result
    }

    // MARK: - Private helpers

    /// ディレクトリ列挙失敗（DES-104 §8.5: cause / suggestion をツール層が参照しやすい形で保持）
    private enum DirectoryEnumerationError: LocalizedError {
        case failed(path: String)

        var errorDescription: String? {
            switch self {
            case .failed(let path):
                return "Failed to enumerate project directory: \(path)"
            }
        }

        var recoverySuggestion: String? {
            "プロジェクトパスのアクセス権限を確認してください。"
        }
    }

    private static func directoryEnumerator(at directory: String, fileManager: FileManager) throws -> FileManager.DirectoryEnumerator {
        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            throw DirectoryEnumerationError.failed(path: directory)
        }
        return enumerator
    }

    private static func compiledGlobRegexes(patterns: [String]) throws -> [NSRegularExpression] {
        try patterns.map { globPattern in
            try NSRegularExpression(pattern: wildcardToRegex(globPattern), options: [.caseInsensitive])
        }
    }

    private static func pathMatchesAnyGlob(relativePath: String, regexes: [NSRegularExpression]) -> Bool {
        let range = NSRange(relativePath.startIndex..., in: relativePath)
        return regexes.contains { $0.firstMatch(in: relativePath, range: range) != nil }
    }

    /// include が空なら `.swift` のみ。exclude がどれかに一致すれば除外優先。
    private static func shouldSearchFile(
        relativePath: String,
        includePatterns: [String],
        excludePatterns: [String],
        includeRegexes: [NSRegularExpression],
        excludeRegexes: [NSRegularExpression]
    ) -> Bool {
        let included: Bool
        if includePatterns.isEmpty {
            included = relativePath.hasSuffix(".swift")
        } else {
            included = pathMatchesAnyGlob(relativePath: relativePath, regexes: includeRegexes)
        }

        guard included else { return false }

        if excludePatterns.isEmpty {
            return true
        }

        let excluded = pathMatchesAnyGlob(relativePath: relativePath, regexes: excludeRegexes)
        return !excluded
    }
}
