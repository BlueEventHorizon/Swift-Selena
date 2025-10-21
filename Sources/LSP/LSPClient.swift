//
//  LSPClient.swift
//  Swift-Selena
//
//  Created on 2025/10/21.
//

import Foundation
import Logging

/// SourceKit-LSPクライアント
///
/// ## 目的
/// SourceKit-LSPとJSON-RPC over stdin/stdoutで通信
///
/// ## 通信方式
/// - stdin: JSON-RPCリクエスト送信
/// - stdout: JSON-RPCレスポンス受信
/// - stderr: ログ出力（無視）
///
/// ## v0.5.1の実装範囲
/// - プロセス起動
/// - Initializeリクエスト送信
/// - 接続確認のみ
///
/// ## v0.5.2での拡張予定
/// - textDocument/referencesリクエスト
/// - レスポンス受信・解析
/// - エラーハンドリング完全実装
class LSPClient {
    private let process: Process
    private let logger: Logger
    private let projectPath: String

    // stdin/stdoutパイプ
    private let inputPipe: Pipe
    private let outputPipe: Pipe
    private let errorPipe: Pipe

    /// 初期化してLSP接続
    ///
    /// ## 処理フロー
    /// 1. sourcekit-lspプロセスを起動
    /// 2. Initializeリクエスト送信
    /// 3. レスポンス待機（簡易実装）
    ///
    /// - Parameters:
    ///   - projectPath: プロジェクトパス
    ///   - logger: ロガー
    /// - Throws: LSP起動・初期化エラー
    init(projectPath: String, logger: Logger) async throws {
        self.projectPath = projectPath
        self.logger = logger
        self.inputPipe = Pipe()
        self.outputPipe = Pipe()
        self.errorPipe = Pipe()

        // SourceKit-LSPプロセスを起動
        self.process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sourcekit-lsp")
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        logger.info("Starting SourceKit-LSP process...")

        do {
            try process.run()
        } catch {
            throw LSPError.processStartFailed(error)
        }

        // Initializeリクエスト送信
        do {
            try await sendInitialize()
            logger.info("LSP Initialize request sent")
        } catch {
            process.terminate()
            throw LSPError.initializeFailed(error)
        }
    }

    /// Initializeリクエスト送信
    ///
    /// ## JSON-RPC形式
    /// ```json
    /// {
    ///   "jsonrpc": "2.0",
    ///   "id": 1,
    ///   "method": "initialize",
    ///   "params": {
    ///     "processId": 12345,
    ///     "rootUri": "file:///path/to/project",
    ///     "capabilities": {}
    ///   }
    /// }
    /// ```
    private func sendInitialize() async throws {
        let processId = ProcessInfo.processInfo.processIdentifier

        let request = """
        Content-Length: 200\r
        \r
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":\(processId),"rootUri":"file://\(projectPath)","capabilities":{}}}
        """

        guard let data = request.data(using: .utf8) else {
            throw LSPError.encodingFailed
        }

        inputPipe.fileHandleForWriting.write(data)

        // v0.5.1: レスポンス受信は簡易実装（成功前提）
        // v0.5.2: レスポンス解析を完全実装
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒待機
    }

    // MARK: - v0.5.2 LSP API実装

    private var messageId = 2  // Initialize=1を使ったので2から

    /// 参照箇所を検索（textDocument/references）
    ///
    /// - Parameters:
    ///   - filePath: ファイルパス
    ///   - line: 行番号（0-indexed）
    ///   - column: 列番号（0-indexed）
    /// - Returns: 参照箇所のリスト
    func findReferences(filePath: String, line: Int, column: Int) async throws -> [LSPLocation] {
        messageId += 1
        let id = messageId

        // textDocument/referencesリクエスト
        let request = """
        {"jsonrpc":"2.0","id":\(id),"method":"textDocument/references","params":{"textDocument":{"uri":"file://\(filePath)"},"position":{"line":\(line),"character":\(column)},"context":{"includeDeclaration":false}}}
        """

        let contentLength = request.utf8.count
        let message = "Content-Length: \(contentLength)\r\n\r\n\(request)"

        guard let data = message.data(using: .utf8) else {
            throw LSPError.encodingFailed
        }

        // リクエスト送信
        inputPipe.fileHandleForWriting.write(data)
        logger.debug("Sent textDocument/references request")

        // レスポンス受信（簡易実装）
        // v0.5.2: 基本的なレスポンス解析
        let response = try await receiveResponse()

        // JSONパース
        guard let jsonData = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let result = json["result"] as? [[String: Any]] else {
            return []  // 参照なし
        }

        // Location解析
        var locations: [LSPLocation] = []
        for loc in result {
            if let uri = loc["uri"] as? String,
               let range = loc["range"] as? [String: Any],
               let start = range["start"] as? [String: Any],
               let line = start["line"] as? Int {
                locations.append(LSPLocation(
                    filePath: uri.replacingOccurrences(of: "file://", with: ""),
                    line: line + 1  // 0-indexed → 1-indexed
                ))
            }
        }

        return locations
    }

    /// レスポンス受信（簡易実装）
    private func receiveResponse() async throws -> String {
        // v0.5.2: 簡易実装（タイムアウト1秒）
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let handle = outputPipe.fileHandleForReading
        guard let data = try? handle.availableData,
              !data.isEmpty,
              let response = String(data: data, encoding: .utf8) else {
            throw LSPError.communicationFailed
        }

        // Content-Lengthヘッダーをスキップ
        if let jsonStart = response.range(of: "{") {
            return String(response[jsonStart.lowerBound...])
        }

        return response
    }

    /// LSP接続を切断
    func disconnect() {
        logger.info("Terminating LSP process...")
        process.terminate()
    }
}

/// LSP位置情報
struct LSPLocation {
    let filePath: String
    let line: Int
}

/// LSPエラー
enum LSPError: Error {
    case processStartFailed(Error)
    case initializeFailed(Error)
    case encodingFailed
    case communicationFailed
    case responseTimeout
}
