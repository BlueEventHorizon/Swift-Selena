//
//  CacheGarbageCollector.swift
//  SwiftMCPServer
//
//  Created by k_terada on 2025/10/04.
//

import Foundation

/// キャッシュのガベージコレクション機能
enum CacheGarbageCollector {
    /// 削除されたファイルのキャッシュを除去
    /// - Returns: 削除されたエントリ数
    static func collect(
        cache: inout [String: FileCacheEntry],
        validFiles: Set<String>
    ) -> Int {
        var removedCount = 0

        for cachedFile in cache.keys {
            if !validFiles.contains(cachedFile) {
                cache.removeValue(forKey: cachedFile)
                removedCount += 1
            }
        }

        return removedCount
    }

    /// LRUベースで古いエントリを削除（メモリ節約）
    /// - Returns: 削除されたエントリ数
    static func evictLRU(
        cache: inout [String: FileCacheEntry],
        maxEntries: Int = 1000
    ) -> Int {
        guard cache.count > maxEntries else { return 0 }

        let sorted = cache.values.sorted { $0.lastAccessed < $1.lastAccessed }
        let toRemove = sorted.prefix(cache.count - maxEntries)

        var removedCount = 0
        for entry in toRemove {
            cache.removeValue(forKey: entry.filePath)
            removedCount += 1
        }

        return removedCount
    }

    /// キャッシュ統計を取得
    static func getStats(cache: [String: FileCacheEntry]) -> CacheStats {
        var stats = CacheStats(
            totalFiles: cache.count,
            filesWithSymbols: 0,
            filesWithImports: 0,
            filesWithTypes: 0,
            filesWithExtensions: 0,
            filesWithWrappers: 0
        )

        for entry in cache.values {
            if entry.symbols != nil { stats.filesWithSymbols += 1 }
            if entry.imports != nil { stats.filesWithImports += 1 }
            if entry.typeConformances != nil { stats.filesWithTypes += 1 }
            if entry.extensions != nil { stats.filesWithExtensions += 1 }
            if entry.propertyWrappers != nil { stats.filesWithWrappers += 1 }
        }

        return stats
    }
}

/// キャッシュ統計情報
struct CacheStats {
    let totalFiles: Int
    var filesWithSymbols: Int
    var filesWithImports: Int
    var filesWithTypes: Int
    var filesWithExtensions: Int
    var filesWithWrappers: Int
}
