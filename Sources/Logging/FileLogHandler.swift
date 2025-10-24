//
//  FileLogHandler.swift
//  Swift-Selena
//
//  Created on 2025/10/21.
//

import Foundation
import Logging

/// ファイルベースのLogHandler
///
/// ## 目的
/// ログをファイルに出力してデバッグを可能にする
///
/// ## ログファイル位置
/// ~/.swift-selena/logs/server.log
///
/// ## 確認方法
/// ```bash
/// tail -f ~/.swift-selena/logs/server.log
/// ```
struct FileLogHandler: LogHandler {
    private let fileHandle: FileHandle
    private let logFilePath: String

    var metadata = Logger.Metadata()
    var logLevel: Logger.Level = .debug  // v0.5.3: デバッグレベルに変更

    init(logFilePath: String) throws {
        self.logFilePath = logFilePath

        // ログディレクトリ作成
        let logDir = URL(fileURLWithPath: logFilePath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        // ログファイル作成または追記モードで開く
        if !FileManager.default.fileExists(atPath: logFilePath) {
            FileManager.default.createFile(atPath: logFilePath, contents: nil)
        }

        guard let handle = FileHandle(forWritingAtPath: logFilePath) else {
            throw FileLogHandlerError.cannotOpenFile
        }

        self.fileHandle = handle
        try handle.seekToEnd()

        // 起動時のセパレータ
        let separator = "\n========== Swift-Selena Started: \(Date()) ==========\n"
        if let data = separator.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let levelIcon: String

        switch level {
        case .trace, .debug:
            levelIcon = "🔍"
        case .info, .notice:
            levelIcon = "ℹ️"
        case .warning:
            levelIcon = "⚠️"
        case .error, .critical:
            levelIcon = "❌"
        }

        let logMessage = "[\(timestamp)] \(levelIcon) [\(level)] \(message)\n"

        if let data = logMessage.data(using: .utf8) {
            try? fileHandle.write(contentsOf: data)
        }
    }
}

enum FileLogHandlerError: Error {
    case cannotOpenFile
}
