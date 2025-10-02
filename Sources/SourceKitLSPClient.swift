//
//  SourceKitLSPClient.swift
//  Selena Personal MCP Server
//
//  Created by k_terada on 2025/10/01.
//

import Foundation

/// 応答管理用のactor（thread-safe）
actor ResponseManager {
    private var pendingResponses: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var responseBuffer = Data()

    func registerResponse(id: Int, continuation: CheckedContinuation<[String: Any], Error>) {
        pendingResponses[id] = continuation
    }

    func removeResponse(id: Int) -> CheckedContinuation<[String: Any], Error>? {
        return pendingResponses.removeValue(forKey: id)
    }

    func appendToBuffer(_ data: Data) {
        responseBuffer.append(data)
    }

    func getBuffer() -> Data {
        return responseBuffer
    }

    func removeFromBuffer(range: Range<Int>) {
        responseBuffer.removeSubrange(range)
    }

    func clearAllResponses() -> [Int: CheckedContinuation<[String: Any], Error>] {
        let pending = pendingResponses
        pendingResponses.removeAll()
        return pending
    }
}

/// SourceKit-LSPとJSON-RPC通信するクライアント
class SourceKitLSPClient {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var messageId = 0
    private var projectPath: String?

    // 応答管理用
    private let responseManager = ResponseManager()
    
    /// プロジェクトを初期化
    func initialize(projectPath: String) async throws {
        self.projectPath = projectPath
        
        // SourceKit-LSPプロセス起動
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["sourcekit-lsp"]
        
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        
        try process.run()

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe

        // バックグラウンドで応答を継続的に読み取る
        startReadingResponses()
        
        // LSP initialize request
        let initRequest = [
            "jsonrpc": "2.0",
            "id": nextId(),
            "method": "initialize",
            "params": [
                "processId": ProcessInfo.processInfo.processIdentifier,
                "rootUri": "file://\(projectPath)",
                "capabilities": [:]
            ]
        ] as [String: Any]
        
        _ = try await sendRequest(initRequest)
        
        // initialized notification
        let initializedNotification = [
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": [:]
        ] as [String: Any]
        
        try sendNotification(initializedNotification)
    }
    
    /// ワークスペース内のシンボル検索
    func findSymbol(query: String) async throws -> String {
        let request = [
            "jsonrpc": "2.0",
            "id": nextId(),
            "method": "workspace/symbol",
            "params": [
                "query": query
            ]
        ] as [String: Any]
        
        let response = try await sendRequest(request)
        return formatSymbolResults(response)
    }
    
    /// ドキュメント内のシンボル一覧取得
    func getDocumentSymbols(filePath: String) async throws -> String {
        // ドキュメントを開く
        try await openDocument(filePath: filePath)
        
        let request = [
            "jsonrpc": "2.0",
            "id": nextId(),
            "method": "textDocument/documentSymbol",
            "params": [
                "textDocument": [
                    "uri": "file://\(filePath)"
                ]
            ]
        ] as [String: Any]
        
        let response = try await sendRequest(request)
        return formatDocumentSymbols(response)
    }
    
    /// 定義へジャンプ
    func getDefinition(filePath: String, line: Int, column: Int) async throws -> String {
        try await openDocument(filePath: filePath)
        
        let request = [
            "jsonrpc": "2.0",
            "id": nextId(),
            "method": "textDocument/definition",
            "params": [
                "textDocument": [
                    "uri": "file://\(filePath)"
                ],
                "position": [
                    "line": line,
                    "character": column
                ]
            ]
        ] as [String: Any]
        
        let response = try await sendRequest(request)
        return formatLocation(response)
    }
    
    /// 参照箇所を検索
    func findReferences(filePath: String, line: Int, column: Int) async throws -> String {
        try await openDocument(filePath: filePath)
        
        let request = [
            "jsonrpc": "2.0",
            "id": nextId(),
            "method": "textDocument/references",
            "params": [
                "textDocument": [
                    "uri": "file://\(filePath)"
                ],
                "position": [
                    "line": line,
                    "character": column
                ],
                "context": [
                    "includeDeclaration": true
                ]
            ]
        ] as [String: Any]
        
        let response = try await sendRequest(request)
        return formatReferences(response)
    }
    
    // MARK: - Private Methods
    
    private func nextId() -> Int {
        messageId += 1
        return messageId
    }
    
    private func openDocument(filePath: String) async throws {
        guard let content = try? String(contentsOfFile: filePath) else {
            throw NSError(domain: "LSPClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to read file: \(filePath)"
            ])
        }
        
        let notification = [
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": [
                "textDocument": [
                    "uri": "file://\(filePath)",
                    "languageId": "swift",
                    "version": 1,
                    "text": content
                ]
            ]
        ] as [String: Any]
        
        try sendNotification(notification)
    }
    
    private func sendRequest(_ request: [String: Any]) async throws -> [String: Any] {
        guard let stdinPipe = stdinPipe else {
            throw NSError(domain: "LSPClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "LSP not initialized"
            ])
        }

        guard let id = request["id"] as? Int else {
            throw NSError(domain: "LSPClient", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Request must have an ID"
            ])
        }

        // 応答を待つためのContinuationを登録
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await responseManager.registerResponse(id: id, continuation: continuation)

                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: request)
                    let message = "Content-Length: \(jsonData.count)\r\n\r\n".data(using: .utf8)! + jsonData
                    stdinPipe.fileHandleForWriting.write(message)
                } catch {
                    if let cont = await responseManager.removeResponse(id: id) {
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    private func sendNotification(_ notification: [String: Any]) throws {
        guard let stdinPipe = stdinPipe else {
            throw NSError(domain: "LSPClient", code: -1)
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: notification)
        let message = "Content-Length: \(jsonData.count)\r\n\r\n".data(using: .utf8)! + jsonData
        
        stdinPipe.fileHandleForWriting.write(message)
    }
    
    // MARK: - Formatters
    
    private func formatSymbolResults(_ response: [String: Any]) -> String {
        guard let result = response["result"] as? [[String: Any]] else {
            return "No symbols found"
        }
        
        var output = "Found \(result.count) symbols:\n\n"
        
        for symbol in result {
            if let name = symbol["name"] as? String,
               let kind = symbol["kind"] as? Int,
               let location = symbol["location"] as? [String: Any],
               let uri = location["uri"] as? String {
                let kindName = symbolKindName(kind)
                output += "[\(kindName)] \(name)\n"
                output += "  Location: \(uri)\n\n"
            }
        }
        
        return output
    }
    
    private func formatDocumentSymbols(_ response: [String: Any]) -> String {
        guard let result = response["result"] as? [[String: Any]] else {
            return "No symbols in document"
        }
        
        var output = "Document Symbols:\n\n"
        
        for symbol in result {
            output += formatSymbol(symbol, indent: 0)
        }
        
        return output
    }
    
    private func formatSymbol(_ symbol: [String: Any], indent: Int) -> String {
        let indentStr = String(repeating: "  ", count: indent)
        var output = ""
        
        if let name = symbol["name"] as? String,
           let kind = symbol["kind"] as? Int {
            let kindName = symbolKindName(kind)
            output += "\(indentStr)[\(kindName)] \(name)\n"
        }
        
        if let children = symbol["children"] as? [[String: Any]] {
            for child in children {
                output += formatSymbol(child, indent: indent + 1)
            }
        }
        
        return output
    }
    
    private func formatLocation(_ response: [String: Any]) -> String {
        guard let result = response["result"] as? [String: Any],
              let uri = result["uri"] as? String,
              let range = result["range"] as? [String: Any],
              let start = range["start"] as? [String: Any],
              let line = start["line"] as? Int,
              let character = start["character"] as? Int else {
            return "Definition not found"
        }
        
        return """
        Definition found:
        File: \(uri)
        Line: \(line + 1), Column: \(character + 1)
        """
    }
    
    private func formatReferences(_ response: [String: Any]) -> String {
        guard let result = response["result"] as? [[String: Any]] else {
            return "No references found"
        }
        
        var output = "Found \(result.count) references:\n\n"
        
        for ref in result {
            if let uri = ref["uri"] as? String,
               let range = ref["range"] as? [String: Any],
               let start = range["start"] as? [String: Any],
               let line = start["line"] as? Int {
                output += "\(uri):\(line + 1)\n"
            }
        }
        
        return output
    }
    
    private func symbolKindName(_ kind: Int) -> String {
        switch kind {
        case 5: return "Class"
        case 10: return "Enum"
        case 11: return "Interface"  // Protocol/Interface
        case 12: return "Function"
        case 13: return "Variable"
        case 14: return "Constant"
        case 23: return "Struct"
        default: return "Symbol(\(kind))"
        }
    }
    
    // MARK: - Response Reading

    private func startReadingResponses() {
        guard let stdoutPipe = stdoutPipe else { return }

        Task {
            let fileHandle = stdoutPipe.fileHandleForReading

            // 非同期でデータを読み続ける
            while true {
                do {
                    // 利用可能なデータを読み取る
                    let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                        fileHandle.readabilityHandler = { handle in
                            let data = handle.availableData
                            fileHandle.readabilityHandler = nil
                            continuation.resume(returning: data)
                        }
                    }

                    if data.isEmpty {
                        // プロセスが終了した
                        break
                    }

                    // バッファに追加
                    await responseManager.appendToBuffer(data)

                    // バッファからメッセージを抽出
                    await processResponseBuffer()

                } catch {
                    print("Error reading LSP response: \(error)")
                    break
                }
            }
        }
    }

    private func processResponseBuffer() async {
        while true {
            let buffer = await responseManager.getBuffer()

            // Content-Lengthヘッダーを探す
            guard let headerEndRange = buffer.range(of: "\r\n\r\n".data(using: .utf8)!) else {
                // ヘッダーが完全に受信されていない
                return
            }

            let headerData = buffer.subdata(in: 0..<headerEndRange.lowerBound)
            guard let headerString = String(data: headerData, encoding: .utf8) else {
                // 無効なヘッダー、バッファをクリア
                await responseManager.removeFromBuffer(range: 0..<buffer.count)
                return
            }

            // Content-Lengthを抽出
            var contentLength = 0
            for line in headerString.components(separatedBy: "\r\n") {
                if line.hasPrefix("Content-Length:") {
                    let lengthString = line.replacingOccurrences(of: "Content-Length:", with: "").trimmingCharacters(in: .whitespaces)
                    contentLength = Int(lengthString) ?? 0
                    break
                }
            }

            if contentLength == 0 {
                // 無効なContent-Length
                await responseManager.removeFromBuffer(range: 0..<buffer.count)
                return
            }

            let jsonStartIndex = headerEndRange.upperBound
            let jsonEndIndex = jsonStartIndex + contentLength

            // JSONデータが完全に受信されているか確認
            if buffer.count < jsonEndIndex {
                // まだ全データが受信されていない
                return
            }

            // JSONを抽出
            let jsonData = buffer.subdata(in: jsonStartIndex..<jsonEndIndex)

            // バッファから処理済みデータを削除
            await responseManager.removeFromBuffer(range: 0..<jsonEndIndex)

            // JSONをパース
            do {
                if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    await handleResponse(json)
                }
            } catch {
                print("Failed to parse JSON: \(error)")
            }
        }
    }

    private func handleResponse(_ json: [String: Any]) async {
        // IDがあればリクエストへの応答
        if let id = json["id"] as? Int {
            if let continuation = await responseManager.removeResponse(id: id) {
                if let error = json["error"] as? [String: Any] {
                    let errorMessage = error["message"] as? String ?? "Unknown error"
                    let nsError = NSError(domain: "LSPClient", code: -3, userInfo: [
                        NSLocalizedDescriptionKey: errorMessage
                    ])
                    continuation.resume(throwing: nsError)
                } else {
                    continuation.resume(returning: json)
                }
            }
        }
        // IDがない場合は通知（現在は無視）
    }

    deinit {
        // 残っているContinuationをキャンセル
        Task {
            let pending = await responseManager.clearAllResponses()

            for (_, continuation) in pending {
                continuation.resume(throwing: NSError(domain: "LSPClient", code: -4, userInfo: [
                    NSLocalizedDescriptionKey: "LSP client deinitialized"
                ]))
            }
        }

        process?.terminate()
    }
}
