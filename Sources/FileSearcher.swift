//
//  FileSearcher.swift
//  SwiftMCPServer
//
//  Created by k_terada on 2025/10/03.
//

import Foundation

/// ファイルシステムベースの検索機能
enum FileSearcher {
    /// ワイルドカードパターンでファイルを検索
    static func findFiles(in directory: String, pattern: String) throws -> [String] {
        var results: [String] = []
        let fileManager = FileManager.default

        let regex = try NSRegularExpression(
            pattern: wildcardToRegex(pattern),
            options: [.caseInsensitive]
        )

        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            throw NSError(domain: "FileSearcher", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to enumerate directory"
            ])
        }

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
    static func searchCode(in directory: String, pattern: String, filePattern: String?) throws -> [(file: String, line: Int, content: String)] {
        var results: [(file: String, line: Int, content: String)] = []
        let fileManager = FileManager.default

        let regex = try NSRegularExpression(pattern: pattern, options: [])

        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            throw NSError(domain: "FileSearcher", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to enumerate directory"
            ])
        }

        for case let file as String in enumerator {
            // 除外ディレクトリをスキップ（v0.5.4: Constants使用）
            let fullPath = (directory as NSString).appendingPathComponent(file)
            if ExcludedDirectories.shouldExclude(fullPath) {
                continue
            }

            let shouldSearch: Bool
            if let filePattern = filePattern {
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
                let fullPath = (directory as NSString).appendingPathComponent(file)
                if let content = try? String(contentsOfFile: fullPath) {
                    let lines = content.components(separatedBy: .newlines)
                    for (lineNumber, lineContent) in lines.enumerated() {
                        let range = NSRange(lineContent.startIndex..., in: lineContent)
                        if regex.firstMatch(in: lineContent, range: range) != nil {
                            results.append((file: fullPath, line: lineNumber + 1, content: lineContent))
                        }
                    }
                }
            }
        }

        return results
    }

    /// パターンにマッチしないファイルを検索（grep -L相当）
    static func searchFilesWithoutPattern(
        in directory: String,
        pattern: String,
        filePattern: String?
    ) throws -> [String] {
        var filesWithoutPattern: [String] = []
        let fileManager = FileManager.default

        let regex = try NSRegularExpression(pattern: pattern, options: [])

        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            throw NSError(domain: "FileSearcher", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to enumerate directory"
            ])
        }

        for case let file as String in enumerator {
            // 除外ディレクトリをスキップ
            let fullPath = (directory as NSString).appendingPathComponent(file)
            if ExcludedDirectories.shouldExclude(fullPath) {
                continue
            }

            let shouldSearch: Bool
            if let filePattern = filePattern {
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

        return filesWithoutPattern.sorted()
    }

    /// ワイルドカードパターンを正規表現に変換
    private static func wildcardToRegex(_ pattern: String) -> String {
        var result = "^"
        for char in pattern {
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
}
