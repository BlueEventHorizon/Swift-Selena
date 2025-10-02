//
//  SourceKitLSPClient.swift
//  Selena Personal MCP Server
//
//  Created by k_terada on 2025/10/01.
//

import Foundation

/// SourceKit-LSPとJSON-RPC通信するクライアント
class SourceKitLSPClient {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var messageId = 0
    private var projectPath: String?
    
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
        
        try await sendRequest(initRequest)
        
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
        guard let stdinPipe = stdinPipe,
              let stdoutPipe = stdoutPipe else {
            throw NSError(domain: "LSPClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "LSP not initialized"
            ])
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: request)
        let message = "Content-Length: \(jsonData.count)\r\n\r\n".data(using: .utf8)! + jsonData
        
        stdinPipe.fileHandleForWriting.write(message)
        
        // レスポンス読み取り（簡易実装）
        try await Task.sleep(for: .milliseconds(100))
        let availableData = stdoutPipe.fileHandleForReading.availableData
        
        if availableData.isEmpty {
            return [:]
        }
        
        // Content-Lengthヘッダーをパース
        guard let responseString = String(data: availableData, encoding: .utf8),
              let jsonStart = responseString.range(of: "\r\n\r\n") else {
            return [:]
        }
        
        let jsonString = String(responseString[jsonStart.upperBound...])
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return [:]
        }
        
        return json
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
        case 12: return "Function"
        case 11: return "Method"
        case 13: return "Variable"
        case 14: return "Constant"
        case 23: return "Struct"
        case 10: return "Enum"
        case 11: return "Protocol"
        default: return "Symbol(\(kind))"
        }
    }
    
    deinit {
        process?.terminate()
    }
}
