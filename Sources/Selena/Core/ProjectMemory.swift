//
//  ProjectMemory.swift
//  SwiftMCPServer
//
//  Created by k_terada on 2025/10/02.
//

import Foundation
import CryptoKit

/// プロジェクトごとの永続化されたメモリ
actor ProjectMemory {
    let projectPath: String
    private let memoryDir: URL
    private let projectName: String
    
    /// キャッシュフォーマットのバージョン（構造変更時にインクリメント）
    private static let cacheVersion = 3

    struct Memory: Codable {
        var cacheVersion: Int
        var lastAnalyzed: Date
        var fileIndex: [String: FileInfo]
        var fileSymbolCache: [String: [SymbolInfo]]  // ファイルパス -> シンボル一覧
        var importCache: [String: [ImportInfo]]
        var typeConformanceCache: [String: TypeConformanceInfo]
        var classDefinitions: Set<String>  // プロジェクト内で定義されたClass名
        var notes: [Note]

        struct FileInfo: Codable {
            let path: String
            let lastModified: Date
        }

        struct SymbolInfo: Codable {
            let name: String
            let kind: String
            let line: Int
        }

        struct ImportInfo: Codable {
            let module: String
            let kind: String?
            let line: Int
        }

        struct TypeConformanceInfo: Codable {
            let typeName: String
            let typeKind: String
            let filePath: String
            let line: Int
            let superclass: String?
            let protocols: [String]
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
            .appendingPathComponent(AppConstants.storageDirectory)
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
            let loaded = try JSONDecoder().decode(Memory.self, from: data)

            // バージョンチェック: 古いバージョンなら再初期化
            if loaded.cacheVersion != Self.cacheVersion {
                self.memory = Self.createEmptyMemory()
                try save()
            } else {
                self.memory = loaded
            }
        } else {
            self.memory = Self.createEmptyMemory()
            try save()
        }
    }

    /// 空のメモリを作成
    private static func createEmptyMemory() -> Memory {
        Memory(
            cacheVersion: cacheVersion,
            lastAnalyzed: Date(),
            fileIndex: [:],
            fileSymbolCache: [:],
            importCache: [:],
            typeConformanceCache: [:],
            classDefinitions: [],
            notes: []
        )
    }

    /// ファイルのシンボル一覧をキャッシュ
    func cacheFileSymbols(filePath: String, symbols: [Memory.SymbolInfo]) {
        // ファイルインデックスも更新
        if let attributes = try? FileManager.default.attributesOfItem(atPath: filePath),
           let modificationDate = attributes[.modificationDate] as? Date {
            memory.fileIndex[filePath] = Memory.FileInfo(
                path: filePath,
                lastModified: modificationDate
            )
        }
        memory.fileSymbolCache[filePath] = symbols
    }

    /// キャッシュからファイルのシンボル一覧を取得
    func getCachedFileSymbols(filePath: String) -> [Memory.SymbolInfo]? {
        guard !isFileModified(path: filePath) else {
            return nil
        }
        return memory.fileSymbolCache[filePath]
    }

    /// 全ファイルのキャッシュ済みシンボルを取得（変更されたファイルは除外）
    func getAllCachedSymbols() -> [String: [Memory.SymbolInfo]] {
        var validCache: [String: [Memory.SymbolInfo]] = [:]
        for (filePath, symbols) in memory.fileSymbolCache {
            if !isFileModified(path: filePath) {
                validCache[filePath] = symbols
            }
        }
        return validCache
    }

    /// ファイルをインデックス（内部用）
    private func indexFile(path: String) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return
        }

        memory.fileIndex[path] = Memory.FileInfo(
            path: path,
            lastModified: modificationDate
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

    /// 型情報をキャッシュ
    func cacheTypeConformance(typeName: String, typeInfo: Memory.TypeConformanceInfo) {
        memory.typeConformanceCache[typeName] = typeInfo
    }

    /// キャッシュから型情報を取得
    func getCachedTypeConformance(typeName: String) -> Memory.TypeConformanceInfo? {
        guard let cached = memory.typeConformanceCache[typeName] else {
            return nil
        }
        // ファイルが変更されていたらキャッシュ無効
        guard !isFileModified(path: cached.filePath) else {
            return nil
        }
        return cached
    }

    /// 全型情報を取得
    func getAllTypeConformances() -> [String: Memory.TypeConformanceInfo] {
        return memory.typeConformanceCache
    }

    /// Class定義を追加
    func addClassDefinition(_ className: String) {
        memory.classDefinitions.insert(className)
    }

    /// Class定義を一括追加
    func addClassDefinitions(_ classNames: [String]) {
        for name in classNames {
            memory.classDefinitions.insert(name)
        }
    }

    /// Class定義を取得
    func getClassDefinitions() -> Set<String> {
        return memory.classDefinitions
    }

    /// Class定義をクリア
    func clearClassDefinitions() {
        memory.classDefinitions.removeAll()
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
        #if DEBUG
        // デバッグ時: 実際に使用されているキャッシュ情報を表示
        let symbolCacheCount = memory.fileSymbolCache.count
        let importCacheCount = memory.importCache.count
        let typeCacheCount = memory.typeConformanceCache.count

        return """
        📊 デバッグ統計

        プロジェクト名: \(projectName)
        シンボルキャッシュ: \(symbolCacheCount)ファイル
        インポートキャッシュ: \(importCacheCount)ファイル
        型情報キャッシュ: \(typeCacheCount)件
        """
        #else
        return ""
        #endif
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
        memory.fileSymbolCache.removeAll()
        memory.importCache.removeAll()
        memory.typeConformanceCache.removeAll()
        memory.fileIndex.removeAll()
        try save()
    }
}
