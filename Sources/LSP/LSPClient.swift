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

    /// LSP接続を切断
    func disconnect() {
        logger.info("Terminating LSP process...")
        process.terminate()
    }
}

/// LSPエラー
enum LSPError: Error {
    case processStartFailed(Error)
    case initializeFailed(Error)
    case encodingFailed
    case communicationFailed
}
