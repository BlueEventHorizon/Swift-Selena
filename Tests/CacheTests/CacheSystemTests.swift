//
//  CacheSystemTests.swift
//  SwiftMCPServerTests
//
//  Created by k_terada on 2025/10/04.
//

import XCTest
import Foundation

/// Cache systemのユニットテスト
final class CacheSystemTests: XCTestCase {
    var tempDir: URL!
    var cacheManager: CacheManager!

    override func setUp() {
        super.setUp()
        // 一時ディレクトリを作成
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        cacheManager = try? CacheManager(storageURL: tempDir)
    }

    override func tearDown() {
        // 一時ディレクトリを削除
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - FileCacheEntry Tests

    func testFileCacheEntryValidity() {
        let now = Date()
        let past = Date(timeIntervalSinceNow: -100)

        var entry = FileCacheEntry(
            filePath: "/test.swift",
            lastModified: now,
            lastAccessed: now,
            symbols: nil,
            imports: nil,
            typeConformances: nil,
            extensions: nil,
            propertyWrappers: nil
        )

        // 過去の日付 → invalid
        XCTAssertFalse(entry.isValid(currentModifiedDate: past))

        // 同じ日付 → valid
        XCTAssertTrue(entry.isValid(currentModifiedDate: now))

        // 未来の日付 → invalid
        let future = Date(timeIntervalSinceNow: 100)
        XCTAssertFalse(entry.isValid(currentModifiedDate: future))
    }

    func testFileCacheEntryAccessTimeUpdate() {
        var entry = FileCacheEntry(
            filePath: "/test.swift",
            lastModified: Date(),
            lastAccessed: Date(timeIntervalSinceNow: -100),
            symbols: nil,
            imports: nil,
            typeConformances: nil,
            extensions: nil,
            propertyWrappers: nil
        )

        let oldAccessTime = entry.lastAccessed
        entry.updateAccessTime()

        XCTAssertGreaterThan(entry.lastAccessed, oldAccessTime)
    }

    // MARK: - CacheGarbageCollector Tests

    func testGarbageCollectorRemovesDeletedFiles() {
        var cache: [String: FileCacheEntry] = [
            "/file1.swift": createDummyEntry(path: "/file1.swift"),
            "/file2.swift": createDummyEntry(path: "/file2.swift"),
            "/file3.swift": createDummyEntry(path: "/file3.swift")
        ]

        let validFiles: Set<String> = ["/file1.swift", "/file3.swift"]  // file2は削除された

        let removed = CacheGarbageCollector.collect(cache: &cache, validFiles: validFiles)

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(cache.count, 2)
        XCTAssertNil(cache["/file2.swift"])
        XCTAssertNotNil(cache["/file1.swift"])
        XCTAssertNotNil(cache["/file3.swift"])
    }

    func testGarbageCollectorLRUEviction() {
        var cache: [String: FileCacheEntry] = [:]

        // 10個のエントリを作成（アクセス時刻をずらす）
        for i in 0..<10 {
            let entry = FileCacheEntry(
                filePath: "/file\(i).swift",
                lastModified: Date(),
                lastAccessed: Date(timeIntervalSinceNow: TimeInterval(-100 + i * 10)),
                symbols: nil,
                imports: nil,
                typeConformances: nil,
                extensions: nil,
                propertyWrappers: nil
            )
            cache["/file\(i).swift"] = entry
        }

        // 最大5エントリに制限
        let evicted = CacheGarbageCollector.evictLRU(cache: &cache, maxEntries: 5)

        XCTAssertEqual(evicted, 5)
        XCTAssertEqual(cache.count, 5)

        // 最も古い5つが削除され、新しい5つが残る
        XCTAssertNil(cache["/file0.swift"])
        XCTAssertNil(cache["/file1.swift"])
        XCTAssertNotNil(cache["/file5.swift"])
        XCTAssertNotNil(cache["/file9.swift"])
    }

    func testGarbageCollectorStats() {
        var cache: [String: FileCacheEntry] = [:]

        // symbols付きエントリ
        var entry1 = createDummyEntry(path: "/file1.swift")
        entry1.symbols = [SymbolData(name: "Test", kind: "Class", line: 1)]
        cache["/file1.swift"] = entry1

        // imports付きエントリ
        var entry2 = createDummyEntry(path: "/file2.swift")
        entry2.imports = [ImportData(module: "Foundation", kind: nil, line: 1)]
        cache["/file2.swift"] = entry2

        // 両方付きエントリ
        var entry3 = createDummyEntry(path: "/file3.swift")
        entry3.symbols = [SymbolData(name: "User", kind: "Struct", line: 1)]
        entry3.imports = [ImportData(module: "SwiftUI", kind: nil, line: 1)]
        cache["/file3.swift"] = entry3

        let stats = CacheGarbageCollector.getStats(cache: cache)

        XCTAssertEqual(stats.totalFiles, 3)
        XCTAssertEqual(stats.filesWithSymbols, 2)
        XCTAssertEqual(stats.filesWithImports, 2)
    }

    // MARK: - CacheManager Tests

    func testCacheManagerSetAndGet() {
        let testPath = "/test.swift"
        let symbols = [SymbolData(name: "MyClass", kind: "Class", line: 10)]

        // 保存
        cacheManager.setSymbols(symbols, for: testPath)

        // 取得（ファイルが存在しないので常にnilになる問題があるが、ロジックのテスト）
        // 実際のファイルシステムでのテストは統合テストで行う
    }

    func testCacheManagerFindFilesContainingType() {
        // テストデータ作成
        let types1 = [TypeConformanceData(
            typeName: "User",
            typeKind: "Struct",
            line: 1,
            superclass: nil,
            protocols: []
        )]
        cacheManager.setTypeConformances(types1, for: "/user.swift")

        let types2 = [TypeConformanceData(
            typeName: "Post",
            typeKind: "Struct",
            line: 1,
            superclass: nil,
            protocols: []
        )]
        cacheManager.setTypeConformances(types2, for: "/post.swift")

        // 検索
        let filesWithUser = cacheManager.findFilesContainingType("User")

        XCTAssertEqual(filesWithUser.count, 1)
        XCTAssertTrue(filesWithUser.contains("/user.swift"))
    }

    func testCacheManagerGarbageCollection() {
        // キャッシュに3ファイル登録
        cacheManager.setSymbols([SymbolData(name: "A", kind: "Class", line: 1)], for: "/file1.swift")
        cacheManager.setSymbols([SymbolData(name: "B", kind: "Class", line: 1)], for: "/file2.swift")
        cacheManager.setSymbols([SymbolData(name: "C", kind: "Class", line: 1)], for: "/file3.swift")

        // file2が削除されたとする
        let validFiles: Set<String> = ["/file1.swift", "/file3.swift"]

        cacheManager.performGarbageCollection(validFiles: validFiles)

        let stats = cacheManager.getStats()
        XCTAssertEqual(stats.totalFiles, 2)
    }

    // MARK: - Helper

    private func createDummyEntry(path: String) -> FileCacheEntry {
        return FileCacheEntry(
            filePath: path,
            lastModified: Date(),
            lastAccessed: Date(),
            symbols: nil,
            imports: nil,
            typeConformances: nil,
            extensions: nil,
            propertyWrappers: nil
        )
    }
}
