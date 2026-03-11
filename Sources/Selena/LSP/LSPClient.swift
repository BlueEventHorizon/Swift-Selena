//
//  LSPClient.swift
//  Swift-Selena
//
//  Created on 2025/10/21.
//
//  [Code Header Format]
//
//  目的
//  - SourceKit-LSPプロセスを起動し、JSON-RPC over stdin/stdoutで通信
//  - LSPレスポンスをバイト単位バッファ（Data）で管理し、マルチバイト文字を正確に処理
//
//  主要機能
//  - LSPプロセス起動・初期化（initialize + initialized通知）
//  - textDocument/didOpen通知送信
//  - textDocument/documentSymbol・prepareTypeHierarchy リクエスト送信と結果取得
//  - Content-Lengthバイト数に基づくレスポンス切り出し（非同期通知スキップ対応）
//
//  含まれる型
//  - LSPClient: LSP通信クライアント本体
//  - LSPLocation: ファイルパスと行番号の位置情報
//  - LSPDocumentSymbol: ドキュメントシンボル情報
//  - LSPTypeHierarchy: 型階層情報
//  - LSPError: LSP通信エラー種別
//
//  関連型
//  - Pipe, Process, FileHandle（プロセス間通信）
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

        // v0.5.3: SIGPIPEを無視（パイプ書き込み時のクラッシュ防止）
        signal(SIGPIPE, SIG_IGN)

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

        // initializeリクエスト
        let jsonRequest = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":\(processId),"rootUri":"file://\(projectPath)","capabilities":{}}}
        """

        let contentLength = jsonRequest.utf8.count
        let request = "Content-Length: \(contentLength)\r\n\r\n\(jsonRequest)"

        guard let data = request.data(using: .utf8) else {
            throw LSPError.encodingFailed
        }

        // v0.5.3: SIGPIPE対策
        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            logger.error("Failed to write initialize request: \(error)")
            throw LSPError.communicationFailed
        }

        // v0.5.3: Initializeレスポンス待機と読み捨て
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒待機

        // Initializeレスポンスを読み捨てる（バッファをクリア）
        do {
            let initResponse = try await receiveResponse()
            logger.debug("Initialize response received (discarded): \(initResponse.prefix(100))...")
        } catch {
            logger.warning("Failed to read initialize response: \(error)")
            // エラーでも継続（レスポンスがない可能性）
        }

        // v0.5.3: initialized通知を送信（LSPプロトコル必須）
        let initializedNotification = """
        {"jsonrpc":"2.0","method":"initialized","params":{}}
        """
        let initializedLength = initializedNotification.utf8.count
        let initializedMessage = "Content-Length: \(initializedLength)\r\n\r\n\(initializedNotification)"

        if let initializedData = initializedMessage.data(using: .utf8) {
            do {
                try inputPipe.fileHandleForWriting.write(contentsOf: initializedData)
                logger.info("LSP initialized notification sent")
            } catch {
                logger.error("Failed to send initialized notification: \(error)")
                // 失敗してもエラーにしない（継続を試みる）
            }
        }
    }

    // MARK: - v0.5.2 LSP API実装

    private var messageId = 2  // Initialize=1を使ったので2から
    private var openedFiles = Set<String>()  // v0.5.3: 開いたファイルを記録
    /// 受信バッファ（Data型でバイト単位管理、分断受信に対応）
    private var receiveBuffer = Data()

    /// textDocument/didOpen通知を送信
    ///
    /// - Parameter filePath: ファイルパス
    private func sendDidOpen(filePath: String) async throws {
        // 既に開いている場合はスキップ
        if openedFiles.contains(filePath) {
            return
        }

        // ファイル内容を読み取る
        guard let fileContent = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            logger.warning("Cannot read file for didOpen: \(filePath)")
            return
        }

        // Codable構造体でJSONを安全に組み立てる（文字列補間によるエスケープ漏れを防止）
        let notification = DidOpenNotification(
            params: .init(
                textDocument: .init(
                    uri: "file://\(filePath)",
                    languageId: "swift",
                    version: 1,
                    text: fileContent
                )
            )
        )

        // JSONEncoderでエンコード（特殊文字のエスケープはEncoderが自動処理）
        let jsonData: Data
        do {
            jsonData = try JSONEncoder().encode(notification)
        } catch {
            throw LSPError.encodingFailed
        }

        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw LSPError.encodingFailed
        }

        // Content-LengthはJSONバイト列のcountを使用
        let header = "Content-Length: \(jsonData.count)\r\n\r\n"

        guard let messageData = (header + jsonString).data(using: .utf8) else {
            throw LSPError.encodingFailed
        }

        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: messageData)
            openedFiles.insert(filePath)
            logger.debug("Sent textDocument/didOpen for \(filePath)")
        } catch {
            logger.error("Failed to send didOpen: \(error)")
            throw LSPError.communicationFailed
        }

        // didOpenのレスポンスはない（通知なので）、少し待機
        try await Task.sleep(nanoseconds: 100_000_000)  // 0.1秒
    }

    // MARK: - didOpen用Codable構造体

    /// textDocument/didOpen通知のJSON構造
    private struct DidOpenNotification: Encodable {
        /// JSON-RPCバージョン
        let jsonrpc: String = "2.0"
        /// メソッド名
        let method: String = "textDocument/didOpen"
        /// 通知パラメータ
        let params: DidOpenParams

        /// didOpenパラメータ
        struct DidOpenParams: Encodable {
            /// 開くテキストドキュメントの情報
            let textDocument: TextDocumentItem
        }

        /// テキストドキュメント情報
        struct TextDocumentItem: Encodable {
            /// ドキュメントURI（file://スキーム）
            let uri: String
            /// 言語識別子
            let languageId: String
            /// バージョン番号
            let version: Int
            /// ドキュメントの全テキスト内容
            let text: String
        }
    }

    /// ドキュメントシンボルを取得（textDocument/documentSymbol）
    ///
    /// - Parameter filePath: ファイルパス
    /// - Returns: ドキュメントシンボルのリスト
    func documentSymbol(filePath: String) async throws -> [LSPDocumentSymbol] {
        // textDocument/didOpenを送信
        try await sendDidOpen(filePath: filePath)

        messageId += 1
        let id = messageId

        // textDocument/documentSymbolリクエスト
        let request = """
        {"jsonrpc":"2.0","id":\(id),"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"file://\(filePath)"}}}
        """

        let contentLength = request.utf8.count
        let message = "Content-Length: \(contentLength)\r\n\r\n\(request)"

        guard let data = message.data(using: .utf8) else {
            throw LSPError.encodingFailed
        }

        // プロセス状態確認
        if !process.isRunning {
            logger.error("LSP process is not running!")
            throw LSPError.processTerminated
        }

        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
            logger.debug("Sent textDocument/documentSymbol request")
        } catch {
            logger.error("Failed to write to LSP pipe: \(error)")
            throw LSPError.communicationFailed
        }

        // レスポンス受信
        let response = try await receiveResponse()
        logger.info("📋 LSP documentSymbol response (length=\(response.count))")
        logger.info("---START---")
        logger.info("\(response)")
        logger.info("---END---")

        // JSONパース
        guard let jsonData = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            logger.warning("Failed to parse LSP documentSymbol response as JSON")
            return []
        }

        // エラーチェック
        if let error = json["error"] as? [String: Any] {
            logger.error("LSP returned error: \(error)")
            return []
        }

        guard let result = json["result"] as? [[String: Any]] else {
            logger.info("LSP documentSymbol result is empty or invalid")
            return []
        }

        // DocumentSymbol解析（階層構造を再帰的に展開）
        var symbols: [LSPDocumentSymbol] = []
        for symbol in result {
            parseDocumentSymbol(symbol, into: &symbols)
        }

        return symbols
    }

    /// DocumentSymbolを再帰的に解析（階層構造対応）
    private func parseDocumentSymbol(_ symbol: [String: Any], into symbols: inout [LSPDocumentSymbol]) {
        if let name = symbol["name"] as? String,
           let kind = symbol["kind"] as? Int,
           let range = symbol["range"] as? [String: Any],
           let start = range["start"] as? [String: Any],
           let line = start["line"] as? Int {

            let detail = symbol["detail"] as? String

            symbols.append(LSPDocumentSymbol(
                name: name,
                kind: kind,
                detail: detail,
                line: line + 1  // 0-indexed → 1-indexed
            ))

            // 子要素を再帰的に処理
            if let children = symbol["children"] as? [[String: Any]] {
                for child in children {
                    parseDocumentSymbol(child, into: &symbols)
                }
            }
        }
    }

    /// 型階層を取得（textDocument/prepareTypeHierarchy）
    ///
    /// - Parameters:
    ///   - filePath: ファイルパス
    ///   - line: 行番号（0-indexed）
    ///   - column: 列番号（0-indexed）
    /// - Returns: 型階層情報（最初の1件のみ）
    func typeHierarchy(filePath: String, line: Int, column: Int) async throws -> LSPTypeHierarchy? {
        // textDocument/didOpenを送信
        try await sendDidOpen(filePath: filePath)

        messageId += 1
        let id = messageId

        // textDocument/prepareTypeHierarchyリクエスト
        let request = """
        {"jsonrpc":"2.0","id":\(id),"method":"textDocument/prepareTypeHierarchy","params":{"textDocument":{"uri":"file://\(filePath)"},"position":{"line":\(line),"character":\(column)}}}
        """

        let contentLength = request.utf8.count
        let message = "Content-Length: \(contentLength)\r\n\r\n\(request)"

        guard let data = message.data(using: .utf8) else {
            throw LSPError.encodingFailed
        }

        // プロセス状態確認
        if !process.isRunning {
            logger.error("LSP process is not running!")
            throw LSPError.processTerminated
        }

        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
            logger.debug("Sent textDocument/prepareTypeHierarchy request")
        } catch {
            logger.error("Failed to write to LSP pipe: \(error)")
            throw LSPError.communicationFailed
        }

        // レスポンス受信
        let response = try await receiveResponse()
        logger.info("📋 LSP typeHierarchy response (length=\(response.count))")
        logger.info("---START---")
        logger.info("\(response)")
        logger.info("---END---")

        // JSONパース
        guard let jsonData = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            logger.warning("Failed to parse LSP typeHierarchy response as JSON")
            return nil
        }

        // エラーチェック
        if let error = json["error"] as? [String: Any] {
            logger.error("LSP returned error: \(error)")
            return nil
        }

        guard let result = json["result"] as? [[String: Any]],
              let first = result.first else {
            logger.info("LSP typeHierarchy result is empty")
            return nil
        }

        // TypeHierarchy解析
        if let name = first["name"] as? String,
           let kind = first["kind"] as? Int {
            let detail = first["detail"] as? String

            return LSPTypeHierarchy(
                name: name,
                kind: kind,
                detail: detail
            )
        }

        return nil
    }

    /// レスポンス受信（Content-Length対応・バイト単位バッファ版）
    ///
    /// ## 修正内容（バイト単位対応）
    /// - バッファを `Data` 型で管理し、`Content-Length`（バイト数）と正確に比較
    /// - マルチバイト文字（日本語パス等）を含む JSON でも正しく動作
    /// - 分断受信に対応するため、`receiveBuffer` インスタンス変数に未処理データを保持
    private func receiveResponse() async throws -> String {
        // v0.5.5: 非同期通知をスキップして、応答のみ取得
        // v0.6.1: タイムアウト追加（10秒）
        // v0.6.x: バッファをDataで管理してバイト単位処理に修正
        let handle = outputPipe.fileHandleForReading
        let timeoutSeconds = 10
        var elapsedMs = 0

        // ヘッダとボディの区切りバイト列
        let separator = "\r\n\r\n".data(using: .utf8)!

        // 非同期通知をスキップして応答（id付き）を探す
        while elapsedMs < timeoutSeconds * 1000 {
            // 新たに到着したデータをバッファに追記
            let arrived = handle.availableData
            if !arrived.isEmpty {
                receiveBuffer.append(arrived)
            }

            // バッファから完結したメッセージを取り出せる限りループ
            while true {
                // ヘッダ終端（\r\n\r\n）をData上で検索
                guard let separatorRange = receiveBuffer.range(of: separator) else {
                    break  // ヘッダー不完全、次の読み取りを待つ
                }

                // ヘッダ部分をStringに変換してContent-Lengthを取得
                let headerData = receiveBuffer[receiveBuffer.startIndex..<separatorRange.lowerBound]
                guard let headerText = String(data: headerData, encoding: .utf8) else {
                    throw LSPError.communicationFailed
                }

                // Content-Lengthの値（バイト数）を取得
                var contentLength: Int?
                for line in headerText.split(separator: "\r\n") {
                    if line.hasPrefix("Content-Length: ") {
                        let lengthStr = line.replacingOccurrences(of: "Content-Length: ", with: "")
                        contentLength = Int(lengthStr.trimmingCharacters(in: .whitespaces))
                        break
                    }
                }

                guard let length = contentLength else {
                    throw LSPError.communicationFailed
                }

                // ボディ開始インデックス（バイト位置）
                let bodyStart = separatorRange.upperBound

                // バッファ内のボディバイト数を確認
                let availableBodyBytes = receiveBuffer.count - (bodyStart - receiveBuffer.startIndex)
                if availableBodyBytes < length {
                    break  // ボディ不完全、次の読み取りを待つ
                }

                // Content-Length バイト分だけボディをスライス
                let bodyEnd = receiveBuffer.index(bodyStart, offsetBy: length)
                let jsonData = receiveBuffer[bodyStart..<bodyEnd]

                // 処理済みバイトをバッファから除去
                receiveBuffer = Data(receiveBuffer[bodyEnd...])

                // バイト列をUTF-8文字列に変換
                guard let jsonPart = String(data: jsonData, encoding: .utf8) else {
                    throw LSPError.communicationFailed
                }

                // メッセージ種別を判定（id有無）
                if jsonPart.contains("\"id\":") {
                    // 応答メッセージ（id付き）→ これを返す
                    return jsonPart
                } else {
                    // 非同期通知（method付き、id無し）→ スキップ
                    logger.debug("Skipping async notification: \(jsonPart.prefix(100))...")
                    continue
                }
            }

            // データなし or 不完全、100ms待機してリトライ
            try await Task.sleep(nanoseconds: 100_000_000)
            elapsedMs += 100
        }

        // タイムアウト
        logger.warning("LSP response timeout after \(timeoutSeconds) seconds")
        throw LSPError.responseTimeout
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

/// LSPドキュメントシンボル（v0.5.4）
struct LSPDocumentSymbol {
    let name: String
    let kind: Int
    let detail: String?
    let line: Int
}

/// LSP型階層（v0.5.4）
struct LSPTypeHierarchy {
    let name: String
    let kind: Int
    let detail: String?
}

/// LSPエラー
enum LSPError: Error {
    case processStartFailed(Error)
    case initializeFailed(Error)
    case encodingFailed
    case communicationFailed
    case responseTimeout
    case processTerminated  // v0.5.3
}
