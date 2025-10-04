//
//  CacheManager.swift
//  SwiftMCPServer
//
//  Created by k_terada on 2025/10/04.
//

import Foundation

/// ファイル単位のキャッシュ管理システム
class CacheManager: Codable {
    private var fileCache: [String: FileCacheEntry]
    private var lastCleanup: Date
    private var requestCount: Int
    private let storageURL: URL

    enum CodingKeys: String, CodingKey {
        case fileCache
        case lastCleanup
        case requestCount
    }

    // 初期化
    init(storageURL: URL) throws {
        self.storageURL = storageURL
        self.fileCache = [:]
        self.lastCleanup = Date()
        self.requestCount = 0

        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        try load()
    }

    // MARK: - File Modification Check

    /// ファイルが変更されたかチェック
    func isFileModified(path: String) -> Bool {
        guard let entry = fileCache[path] else { return true }
        guard let modDate = getFileModificationDate(path) else { return true }
        return !entry.isValid(currentModifiedDate: modDate)
    }

    private func getFileModificationDate(_ path: String) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    // MARK: - Cache Get Methods

    func getSymbols(for path: String) -> [SymbolData]? {
        guard !isFileModified(path: path) else { return nil }
        updateAccessTime(for: path)
        return fileCache[path]?.symbols
    }

    func getImports(for path: String) -> [ImportData]? {
        guard !isFileModified(path: path) else { return nil }
        updateAccessTime(for: path)
        return fileCache[path]?.imports
    }

    func getTypeConformances(for path: String) -> [TypeConformanceData]? {
        guard !isFileModified(path: path) else { return nil }
        updateAccessTime(for: path)
        return fileCache[path]?.typeConformances
    }

    func getExtensions(for path: String) -> [ExtensionData]? {
        guard !isFileModified(path: path) else { return nil }
        updateAccessTime(for: path)
        return fileCache[path]?.extensions
    }

    func getPropertyWrappers(for path: String) -> [PropertyWrapperData]? {
        guard !isFileModified(path: path) else { return nil }
        updateAccessTime(for: path)
        return fileCache[path]?.propertyWrappers
    }

    private func updateAccessTime(for path: String) {
        fileCache[path]?.updateAccessTime()
    }

    // MARK: - Cache Set Methods

    func setSymbols(_ symbols: [SymbolData], for path: String) {
        updateOrCreateEntry(path: path) { entry in
            entry.symbols = symbols
        }
    }

    func setImports(_ imports: [ImportData], for path: String) {
        updateOrCreateEntry(path: path) { entry in
            entry.imports = imports
        }
    }

    func setTypeConformances(_ types: [TypeConformanceData], for path: String) {
        updateOrCreateEntry(path: path) { entry in
            entry.typeConformances = types
        }
    }

    func setExtensions(_ extensions: [ExtensionData], for path: String) {
        updateOrCreateEntry(path: path) { entry in
            entry.extensions = extensions
        }
    }

    func setPropertyWrappers(_ wrappers: [PropertyWrapperData], for path: String) {
        updateOrCreateEntry(path: path) { entry in
            entry.propertyWrappers = wrappers
        }
    }

    private func updateOrCreateEntry(path: String, update: (inout FileCacheEntry) -> Void) {
        guard let modDate = getFileModificationDate(path) else { return }

        if var entry = fileCache[path] {
            update(&entry)
            entry.lastAccessed = Date()
            fileCache[path] = entry
        } else {
            var newEntry = FileCacheEntry(
                filePath: path,
                lastModified: modDate,
                lastAccessed: Date(),
                symbols: nil,
                imports: nil,
                typeConformances: nil,
                extensions: nil,
                propertyWrappers: nil
            )
            update(&newEntry)
            fileCache[path] = newEntry
        }
    }

    // MARK: - Search Helpers

    /// 特定の型を含むファイルを検索
    func findFilesContainingType(_ typeName: String) -> [String] {
        return fileCache.values
            .filter { $0.typeConformances?.contains(where: { $0.typeName == typeName }) ?? false }
            .map { $0.filePath }
    }

    /// 特定のシンボルを含むファイルを検索
    func findFilesWithSymbol(_ symbolName: String) -> [String] {
        return fileCache.values
            .filter { $0.symbols?.contains(where: { $0.name == symbolName }) ?? false }
            .map { $0.filePath }
    }

    /// 全ての型情報を取得
    func getAllTypeConformances() -> [String: TypeConformanceData] {
        var result: [String: TypeConformanceData] = [:]
        for entry in fileCache.values {
            if let types = entry.typeConformances {
                for type in types {
                    result[type.typeName] = type
                }
            }
        }
        return result
    }

    // MARK: - Garbage Collection

    /// ガベージコレクションを実行
    func performGarbageCollection(validFiles: Set<String>) {
        let removed = CacheGarbageCollector.collect(cache: &fileCache, validFiles: validFiles)
        let evicted = CacheGarbageCollector.evictLRU(cache: &fileCache, maxEntries: 1000)

        if removed > 0 || evicted > 0 {
            print("Cache GC: Removed \(removed) deleted files, evicted \(evicted) LRU entries")
        }

        lastCleanup = Date()
    }

    /// 自動GC判定（常に実行、正確性最優先）
    func checkAndRunGC(validFiles: Set<String>) {
        // 常に実行: 削除ファイルのチェック（正確性のため）
        let removed = CacheGarbageCollector.collect(cache: &fileCache, validFiles: validFiles)

        // 常に実行: LRU削除（ただしキャッシュサイズが閾値超過時のみ）
        var evicted = 0
        if fileCache.count > 1000 {
            evicted = CacheGarbageCollector.evictLRU(cache: &fileCache, maxEntries: 1000)
        }

        if removed > 0 || evicted > 0 {
            print("Cache GC: Removed \(removed) deleted files, evicted \(evicted) LRU entries")
        }
    }

    /// キャッシュ統計を取得
    func getStats() -> CacheStats {
        return CacheGarbageCollector.getStats(cache: fileCache)
    }

    // MARK: - Persistence

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: storageURL.appendingPathComponent("cache.json"))
    }

    private func load() throws {
        let url = storageURL.appendingPathComponent("cache.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(CacheManager.self, from: data)
        self.fileCache = decoded.fileCache
        self.lastCleanup = decoded.lastCleanup
        self.requestCount = decoded.requestCount
    }

    // Codable conformance
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fileCache = try container.decode([String: FileCacheEntry].self, forKey: .fileCache)
        self.lastCleanup = try container.decode(Date.self, forKey: .lastCleanup)
        self.requestCount = try container.decode(Int.self, forKey: .requestCount)
        self.storageURL = URL(fileURLWithPath: "/tmp")  // デコード時は仮のURL
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fileCache, forKey: .fileCache)
        try container.encode(lastCleanup, forKey: .lastCleanup)
        try container.encode(requestCount, forKey: .requestCount)
    }
}
