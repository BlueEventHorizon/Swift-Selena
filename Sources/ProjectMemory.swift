//
//  ProjectMemory.swift
//  SwiftMCPServer
//
//  Created by k_terada on 2025/10/02.
//

import Foundation
import CryptoKit

/// プロジェクトごとの永続化されたメモリ
class ProjectMemory {
    let projectPath: String
    private let memoryDir: URL
    private let projectName: String
    
    struct Memory: Codable {
        var lastAnalyzed: Date
        var fileIndex: [String: FileInfo]
        var symbolCache: [String: [SymbolInfo]]
        var importCache: [String: [ImportInfo]]
        var notes: [Note]

        struct FileInfo: Codable {
            let path: String
            let lastModified: Date
            let symbolCount: Int
        }

        struct SymbolInfo: Codable {
            let name: String
            let kind: String
            let filePath: String
            let line: Int
        }

        struct ImportInfo: Codable {
            let module: String
            let kind: String?
            let line: Int
        }

        struct Note: Codable {
            let timestamp: Date
            let content: String
            let tags: [String]
        }
    }
    
    private var memory: Memory
    
    init(projectPath: String) throws {
        self.projectPath = projectPath
        self.projectName = URL(fileURLWithPath: projectPath).lastPathComponent

        // クライアント識別子を環境変数から取得（デフォルトは"default"）
        let clientId = ProcessInfo.processInfo.environment["MCP_CLIENT_ID"] ?? "default"

        // プロジェクトパスのハッシュを生成（同じプロジェクトなら同じハッシュ）
        let projectPathHash = Self.hashProjectPath(projectPath)

        // メモリディレクトリ作成（クライアント＋プロジェクトパスで分離）
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.memoryDir = homeDir
            .appendingPathComponent(".swift-mcp-server")
            .appendingPathComponent("clients")
            .appendingPathComponent(clientId)
            .appendingPathComponent("projects")
            .appendingPathComponent("\(projectName)-\(projectPathHash)")
        
        try FileManager.default.createDirectory(
            at: memoryDir,
            withIntermediateDirectories: true
        )
        
        // メモリをロードまたは初期化
        let memoryFile = memoryDir.appendingPathComponent("memory.json")
        
        if FileManager.default.fileExists(atPath: memoryFile.path) {
            let data = try Data(contentsOf: memoryFile)
            self.memory = try JSONDecoder().decode(Memory.self, from: data)
        } else {
            self.memory = Memory(
                lastAnalyzed: Date(),
                fileIndex: [:],
                symbolCache: [:],
                importCache: [:],
                notes: []
            )
            try save()
        }
    }
    
    /// シンボルをキャッシュ
    func cacheSymbol(name: String, kind: String, filePath: String, line: Int) {
        let symbol = Memory.SymbolInfo(
            name: name,
            kind: kind,
            filePath: filePath,
            line: line
        )
        
        if memory.symbolCache[name] == nil {
            memory.symbolCache[name] = []
        }
        memory.symbolCache[name]?.append(symbol)
    }
    
    /// キャッシュからシンボル検索
    func findCachedSymbol(name: String) -> [Memory.SymbolInfo]? {
        return memory.symbolCache[name]
    }
    
    /// ファイルをインデックス
    func indexFile(path: String, symbolCount: Int) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return
        }
        
        memory.fileIndex[path] = Memory.FileInfo(
            path: path,
            lastModified: modificationDate,
            symbolCount: symbolCount
        )
    }
    
    /// ファイルが変更されたかチェック
    func isFileModified(path: String) -> Bool {
        guard let cachedInfo = memory.fileIndex[path],
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return true
        }

        return modificationDate > cachedInfo.lastModified
    }

    /// Import情報をキャッシュ
    func cacheImports(filePath: String, imports: [Memory.ImportInfo]) {
        memory.importCache[filePath] = imports
    }

    /// キャッシュからImport情報を取得
    func getCachedImports(filePath: String) -> [Memory.ImportInfo]? {
        guard !isFileModified(path: filePath) else {
            return nil
        }
        return memory.importCache[filePath]
    }

    /// 全Import情報を取得
    func getAllImports() -> [String: [Memory.ImportInfo]] {
        return memory.importCache
    }
    
    /// メモを追加
    func addNote(content: String, tags: [String] = []) {
        let note = Memory.Note(
            timestamp: Date(),
            content: content,
            tags: tags
        )
        memory.notes.append(note)
    }
    
    /// メモを検索
    func searchNotes(query: String) -> [Memory.Note] {
        return memory.notes.filter { note in
            note.content.localizedCaseInsensitiveContains(query) ||
            note.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
    
    /// 統計情報を取得
    func getStats() -> String {
        let totalFiles = memory.fileIndex.count
        let totalSymbols = memory.symbolCache.values.reduce(0) { $0 + $1.count }
        let totalNotes = memory.notes.count

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return """
        📊 プロジェクト統計

        プロジェクト名: \(projectName)
        最終解析: \(formatter.string(from: memory.lastAnalyzed))

        インデックス済みファイル: \(totalFiles)
        キャッシュ済みシンボル: \(totalSymbols)
        保存されたメモ: \(totalNotes)
        """
    }

    /// プロジェクトパスをハッシュ化（短い一意な識別子を生成）
    private static func hashProjectPath(_ path: String) -> String {
        let data = Data(path.utf8)
        let hash = SHA256.hash(data: data)
        // 最初の8文字を使用（衝突の可能性は極めて低い）
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
    }
    
    /// メモリを保存
    func save() throws {
        memory.lastAnalyzed = Date()
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(memory)
        
        let memoryFile = memoryDir.appendingPathComponent("memory.json")
        try data.write(to: memoryFile)
    }
    
    /// キャッシュをクリア
    func clearCache() throws {
        memory.symbolCache.removeAll()
        try save()
    }
}
