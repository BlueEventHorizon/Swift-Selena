# キャッシュシステム再設計（v0.4.0）

## 目的

ファイルの増減・変更に対応し、独立性の高いキャッシュシステムを構築する。

## 現状の問題

### 1. キャッシュ無効化の不完全性
- **importCache**: ✅ ファイル単位で無効化可能
- **typeConformanceCache**: ❌ 全体キャッシュのみ、ファイル単位の無効化なし
- **symbolCache, testCases, typeUsages**: ❌ キャッシュ機能なし

### 2. ファイル削除への未対応
```
問題の流れ:
1. user.swiftを削除
2. typeConformanceCacheにUser型情報が残る
3. getTypeHierarchy("User") → 削除済みなのに見つかる ❌
```

### 3. ファイル移動/リネームの未対応
```
1. user.swift → models/user.swift
2. 旧パスと新パスのキャッシュが両方残る
3. 重複データが蓄積 ❌
```

### 4. キャッシュ構造の不統一
- ファイルパスベース: `importCache`
- 型名ベース: `typeConformanceCache`, `symbolCache`
- 混在していて管理が複雑

---

## 設計方針

### 原則
1. **独立性**: 既存コードへの影響を最小化、新規ディレクトリで実装
2. **ファイル単位**: 全キャッシュをファイル単位で統一管理
3. **自動メンテナンス**: ガベージコレクションを自動実行
4. **透明性**: ユーザーが意識する必要なし

---

## アーキテクチャ

### 新規ファイル構成

```
Sources/
├── Cache/                           # 新規ディレクトリ
│   ├── CacheManager.swift           # キャッシュ管理のコア（約200行）
│   ├── FileCacheEntry.swift         # ファイル単位のキャッシュエントリ（約100行）
│   └── CacheGarbageCollector.swift  # ガベージコレクション（約80行）
├── ProjectMemory.swift              # 既存（250行→100行にリファクタリング）
└── SwiftSyntaxAnalyzer.swift        # 既存（CacheManager使用に変更）
```

**合計**: 約380行の新規コード、150行の削減 = 実質230行の追加

---

## データ構造設計

### FileCacheEntry.swift

```swift
/// ファイル単位のキャッシュエントリ
struct FileCacheEntry: Codable {
    // メタデータ
    let filePath: String
    let lastModified: Date
    var lastAccessed: Date

    // 解析結果（Optionalで必要なものだけ保持）
    var symbols: [SymbolData]?
    var imports: [ImportData]?
    var typeConformances: [TypeConformanceData]?
    var extensions: [ExtensionData]?
    var propertyWrappers: [PropertyWrapperData]?

    // キャッシュの有効性チェック
    func isValid(currentModifiedDate: Date) -> Bool {
        return currentModifiedDate <= lastModified
    }

    // LRU用
    mutating func updateAccessTime() {
        lastAccessed = Date()
    }
}

// 各種データ型（Codable）
struct SymbolData: Codable {
    let name: String
    let kind: String
    let line: Int
}

struct ImportData: Codable {
    let module: String
    let kind: String?
    let line: Int
}

struct TypeConformanceData: Codable {
    let typeName: String
    let typeKind: String
    let line: Int
    let superclass: String?
    let protocols: [String]
}

struct ExtensionData: Codable {
    let extendedType: String
    let protocols: [String]
    let line: Int
    let memberCount: Int
}

struct PropertyWrapperData: Codable {
    let propertyName: String
    let wrapperType: String
    let typeName: String?
    let line: Int
}
```

---

### CacheManager.swift

```swift
/// ファイル単位のキャッシュ管理システム
class CacheManager: Codable {
    private var fileCache: [String: FileCacheEntry]
    private var lastCleanup: Date
    private var requestCount: Int
    private let storageURL: URL

    // 初期化・永続化
    init(storageURL: URL) throws {
        self.storageURL = storageURL
        self.fileCache = [:]
        self.lastCleanup = Date()
        self.requestCount = 0
        try load()
    }

    // ファイル変更検知
    func isFileModified(path: String) -> Bool {
        guard let entry = fileCache[path] else { return true }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modDate = attributes[.modificationDate] as? Date else {
            return true
        }
        return !entry.isValid(currentModifiedDate: modDate)
    }

    // キャッシュ取得（型安全）
    func getSymbols(for path: String) -> [SymbolData]? {
        guard !isFileModified(path: path) else { return nil }
        var entry = fileCache[path]
        entry?.updateAccessTime()
        fileCache[path] = entry
        return entry?.symbols
    }

    func getImports(for path: String) -> [ImportData]?
    func getTypeConformances(for path: String) -> [TypeConformanceData]?
    func getExtensions(for path: String) -> [ExtensionData]?
    func getPropertyWrappers(for path: String) -> [PropertyWrapperData]?

    // キャッシュ保存
    func setSymbols(_ symbols: [SymbolData], for path: String) {
        updateOrCreateEntry(path: path) { entry in
            entry.symbols = symbols
        }
    }

    func setImports(_ imports: [ImportData], for path: String)
    func setTypeConformances(_ types: [TypeConformanceData], for path: String)
    func setExtensions(_ extensions: [ExtensionData], for path: String)
    func setPropertyWrappers(_ wrappers: [PropertyWrapperData], for path: String)

    // 高速検索用ヘルパー
    func findFilesContainingType(_ typeName: String) -> [String] {
        return fileCache.values
            .filter { $0.typeConformances?.contains(where: { $0.typeName == typeName }) ?? false }
            .map { $0.filePath }
    }

    func findFilesWithSymbol(_ symbolName: String) -> [String] {
        return fileCache.values
            .filter { $0.symbols?.contains(where: { $0.name == symbolName }) ?? false }
            .map { $0.filePath }
    }

    // ガベージコレクション
    func performGarbageCollection(validFiles: Set<String>) {
        let removed = CacheGarbageCollector.collect(cache: &fileCache, validFiles: validFiles)
        if removed > 0 {
            print("Cache GC: Removed \(removed) stale entries")
        }
        lastCleanup = Date()
    }

    // 自動GC判定（軽量チェック）
    func checkAndRunGC(validFiles: Set<String>) {
        requestCount += 1

        // 条件: 1時間経過 OR 100リクエスト
        let hourPassed = Date().timeIntervalSince(lastCleanup) > 3600
        let requestThreshold = requestCount >= 100

        if hourPassed || requestThreshold {
            performGarbageCollection(validFiles: validFiles)
            requestCount = 0
        }
    }

    // 永続化
    func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: storageURL.appendingPathComponent("cache.json"))
    }

    func load() throws {
        let url = storageURL.appendingPathComponent("cache.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(CacheManager.self, from: data)
        self.fileCache = decoded.fileCache
        self.lastCleanup = decoded.lastCleanup
        self.requestCount = decoded.requestCount
    }

    // ヘルパー
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
                lastAccessed: Date()
            )
            update(&newEntry)
            fileCache[path] = newEntry
        }
    }

    private func getFileModificationDate(_ path: String) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }
}
```

---

### CacheGarbageCollector.swift

```swift
/// キャッシュのガベージコレクション機能
enum CacheGarbageCollector {
    /// 削除されたファイルのキャッシュを除去
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

    /// キャッシュ統計
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

struct CacheStats {
    let totalFiles: Int
    var filesWithSymbols: Int
    var filesWithImports: Int
    var filesWithTypes: Int
    var filesWithExtensions: Int
    var filesWithWrappers: Int
}
```

---

## 使用フロー

### 典型的な使用パターン（analyzeImports）

```swift
static func analyzeImports(projectPath: String, cacheManager: CacheManager) throws -> [String: [ImportInfo]] {
    let swiftFiles = try FileSearcher.findFiles(in: projectPath, pattern: "*.swift")

    // 自動ガベージコレクション（軽量チェック）
    cacheManager.checkAndRunGC(validFiles: Set(swiftFiles))

    var fileImports: [String: [ImportInfo]] = [:]

    for file in swiftFiles {
        // 1. キャッシュから取得を試みる
        if let cached = cacheManager.getImports(for: file) {
            // キャッシュヒット（ファイル未変更）
            fileImports[file] = cached.map { ImportInfo(module: $0.module, kind: $0.kind, symbols: [], line: $0.line) }
            continue
        }

        // 2. キャッシュミス → 解析
        let imports = try listImports(filePath: file)

        // 3. キャッシュに保存
        let cacheData = imports.map { ImportData(module: $0.module, kind: $0.kind, line: $0.line) }
        cacheManager.setImports(cacheData, for: file)

        fileImports[file] = imports
    }

    // 4. 永続化
    try cacheManager.save()

    return fileImports
}
```

---

## ファイル操作シナリオ

### シナリオ1: 新規ファイル追加

```
1. user.swiftを新規作成
2. FileSearcher.findFiles() → user.swiftが含まれる
3. cacheManager.getImports(user.swift) → nil（キャッシュなし）
4. 解析実行
5. cacheManager.setImports() → キャッシュに追加
```

**結果**: ✅ 自動的に解析・キャッシュ

---

### シナリオ2: ファイル変更

```
1. user.swiftを編集（lastModified更新）
2. cacheManager.getImports(user.swift)
   → isFileModified() → true
   → キャッシュ無効、nilを返す
3. 再解析実行
4. cacheManager.setImports() → 新しい内容でキャッシュ更新
```

**結果**: ✅ 自動的に再解析

---

### シナリオ3: ファイル削除

```
1. user.swiftを削除
2. FileSearcher.findFiles() → user.swiftは含まれない
3. checkAndRunGC()実行
   validFiles = {model.swift, view.swift, ...}  // user.swiftなし
4. GarbageCollector.collect()
   → user.swiftのキャッシュエントリを削除
```

**結果**: ✅ 自動的にキャッシュから除去

---

### シナリオ4: ファイル移動

```
1. user.swift → models/user.swift
2. FileSearcher.findFiles() → models/user.swiftを検出
3. checkAndRunGC()実行
   → 旧パス（user.swift）はvalidFilesに含まれない
   → user.swiftのキャッシュ削除
4. models/user.swift → キャッシュなし → 解析 → 新規保存
```

**結果**: ✅ 旧キャッシュ削除、新規解析

---

## ProjectMemory.swiftの変更

### Before（現状）

```swift
class ProjectMemory {
    struct Memory: Codable {
        var symbolCache: [String: [SymbolInfo]]
        var importCache: [String: [ImportInfo]]
        var typeConformanceCache: [String: TypeConformanceInfo]
        // ... 各種キャッシュ
    }

    func cacheImports(...)
    func getCachedImports(...)
    func cacheTypeConformance(...)
    // ... 各種メソッド（約150行）
}
```

### After（新設計）

```swift
class ProjectMemory {
    let projectPath: String
    private let cacheManager: CacheManager  // 委譲
    private var notes: [Note]

    // キャッシュ操作はCacheManagerに委譲
    func getCachedImports(filePath: String) -> [ImportInfo]? {
        return cacheManager.getImports(for: filePath)?.map { ImportInfo(...) }
    }

    func cacheImports(filePath: String, imports: [ImportInfo]) {
        let data = imports.map { ImportData(...) }
        cacheManager.setImports(data, for: filePath)
    }

    // ノート機能は維持
    func addNote(...)
    func searchNotes(...)

    // 統計情報
    func getStats() -> String {
        let stats = cacheManager.getStats()
        return """
        プロジェクト名: \(projectName)
        キャッシュ済みファイル: \(stats.totalFiles)
        ...
        """
    }
}
```

**削減**: 約150行削減（キャッシュロジックをCacheManagerに移譲）

---

## 実装フェーズ

### Phase 1: 基盤実装（1-2時間）
1. `Sources/Cache/`ディレクトリ作成
2. `FileCacheEntry.swift`実装
3. `CacheGarbageCollector.swift`実装
4. `CacheManager.swift`実装

### Phase 2: 統合（1時間）
1. `ProjectMemory.swift`をCacheManager使用に変更
2. `SwiftSyntaxAnalyzer.swift`をCacheManager対応に変更
3. 自動GC呼び出しを各ツールに追加

### Phase 3: テスト（30分）
1. ファイル追加・変更・削除のテスト
2. ガベージコレクションのテスト
3. 既存機能の回帰テスト

### Phase 4: 移行（10分）
1. 旧キャッシュ削除（`~/.swift-selena/`をクリア）
2. ドキュメント更新

**総所要時間**: 約3-4時間

---

## 期待効果

### パフォーマンス
- ✅ キャッシュヒット率向上（ファイル単位で細かく管理）
- ✅ メモリ使用量削減（LRU、GC）
- ✅ ディスク使用量削減（不要キャッシュの自動削除）

### 正確性
- ✅ ファイル削除に対応
- ✅ ファイル移動に対応
- ✅ キャッシュの一貫性保証

### 保守性
- ✅ 独立したモジュール（テスト可能）
- ✅ 責任の明確な分離
- ✅ 将来の機能追加が容易

---

## 破壊的変更

### キャッシュ形式の変更
- 旧: `memory.json`（複数のキャッシュ構造）
- 新: `cache.json`（FileCacheEntry配列）

### 影響
- 既存ユーザー（あなたのみ）は`~/.swift-selena/`を削除して再初期化

---

## リスク管理

### リスク
1. **実装の複雑さ**: 新規380行のコード
2. **バグの可能性**: キャッシュロジックのバグは影響大
3. **移行コスト**: 既存キャッシュが無効化

### 対策
1. **段階的実装**: Phase 1-4に分割
2. **テストの徹底**: 各Phaseでテスト
3. **ロールバック計画**: 問題があれば旧実装に戻せる

---

## 承認ポイント

以下の点について承認をお願いします：

1. ✅ **独立したCache/ディレクトリの作成** - 良いですか？
2. ✅ **ファイル単位キャッシュへの統一** - 良いですか？
3. ✅ **自動ガベージコレクション（1時間/100リクエスト）** - 良いですか？
4. ✅ **破壊的変更（既存キャッシュ無効化）** - 問題ないですか？
5. ✅ **約380行の新規コード** - 実装量は許容範囲ですか？

---

**承認いただければ実装を開始します。**
