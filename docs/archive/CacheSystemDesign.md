# キャッシュシステム設計（v0.4.0 - 実装完了）

## 概要

v0.4.0でファイル単位のキャッシュシステムを実装完了しました。このドキュメントは実装の詳細と使用方法を記載しています。

## 実装完了日

**2025年10月6日** - v0.4.2でリリース

---

## 実装内容

### 1. 新規ファイル構成

```
Sources/
├── Cache/                           # 新規ディレクトリ（実装完了）
│   ├── CacheManager.swift           # キャッシュ管理のコア
│   ├── FileCacheEntry.swift         # ファイル単位のキャッシュエントリ
│   └── CacheGarbageCollector.swift  # ガベージコレクション
├── ProjectMemory.swift              # CacheManager統合済み
└── SwiftSyntaxAnalyzer.swift        # CacheManager対応済み
```

---

## 主な機能

### ✅ 実装済み機能

1. **ファイル単位キャッシュ**
   - 全キャッシュをファイル単位で統一管理
   - ファイル変更検知による自動無効化
   - ファイルの最終更新日時を追跡

2. **自動ガベージコレクション**
   - 削除されたファイルのキャッシュを自動除去
   - 1時間経過 OR 100リクエストで自動実行
   - LRUベースの古いエントリ削除（メモリ節約）

3. **キャッシュ対象**
   - シンボル情報（symbols）
   - Import情報（imports）
   - 型準拠情報（typeConformances）
   - Extension情報（extensions）
   - Property Wrapper情報（propertyWrappers）

4. **透明性**
   - ユーザーが意識する必要なし
   - 自動的にキャッシュとGCを実行
   - パフォーマンス向上を体感

---

## データ構造

### FileCacheEntry

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
    func isValid(currentModifiedDate: Date) -> Bool

    // LRU用アクセス時刻更新
    mutating func updateAccessTime()
}
```

### CacheManager

```swift
/// ファイル単位のキャッシュ管理システム
class CacheManager: Codable {
    private var fileCache: [String: FileCacheEntry]
    private var lastCleanup: Date
    private var requestCount: Int

    // ファイル変更検知
    func isFileModified(path: String) -> Bool

    // キャッシュ取得（型安全）
    func getSymbols(for path: String) -> [SymbolData]?
    func getImports(for path: String) -> [ImportData]?
    func getTypeConformances(for path: String) -> [TypeConformanceData]?
    func getExtensions(for path: String) -> [ExtensionData]?
    func getPropertyWrappers(for path: String) -> [PropertyWrapperData]?

    // キャッシュ保存
    func setSymbols(_ symbols: [SymbolData], for path: String)
    func setImports(_ imports: [ImportData], for path: String)
    // ... 他のsetter

    // 高速検索用ヘルパー
    func findFilesContainingType(_ typeName: String) -> [String]
    func findFilesWithSymbol(_ symbolName: String) -> [String]

    // ガベージコレクション
    func performGarbageCollection(validFiles: Set<String>)
    func checkAndRunGC(validFiles: Set<String>)

    // 永続化
    func save() throws
    func load() throws
}
```

---

## 使用フロー

### 典型的な使用パターン

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
            fileImports[file] = cached.map { ImportInfo(...) }
            continue
        }

        // 2. キャッシュミス → 解析
        let imports = try listImports(filePath: file)

        // 3. キャッシュに保存
        let cacheData = imports.map { ImportData(...) }
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

## パフォーマンス効果

### キャッシュヒット時

- **解析時間**: ほぼ0ms（ディスクI/Oのみ）
- **メモリ使用量**: 最小限（必要なファイルのみロード）

### キャッシュミス時

- 通常通りの解析実行
- 次回以降はキャッシュから高速取得

### ガベージコレクション

- **実行条件**: 1時間経過 OR 100リクエスト
- **実行時間**: 数ms〜数十ms（ファイル数に依存）
- **メモリ削減**: 削除されたファイルのキャッシュを除去

---

## 保存場所

```
~/.swift-selena/clients/{clientId}/projects/{projectName}-{hash}/cache.json
```

- 旧: `memory.json`（複数のキャッシュ構造）
- 新: `cache.json`（FileCacheEntry配列）

---

## 統計情報

`get_project_stats`ツールでキャッシュ統計を確認可能：

```
📊 プロジェクト統計

プロジェクト名: Swift-Selena
最終解析: 2025/10/06 20:49

キャッシュ済みファイル: 24
- シンボル: 18ファイル
- Import: 24ファイル
- 型準拠: 15ファイル
- Extension: 8ファイル
- Property Wrapper: 3ファイル

保存されたメモ: 2
```

---

## 今後の改善点

### v0.5.0での改善候補

1. **並列処理**
   - 複数ファイルの同時解析
   - キャッシュ読み込みの高速化

2. **インクリメンタル解析の強化**
   - ファイル間依存関係の追跡
   - 変更の影響範囲を最小化

3. **キャッシュ戦略の最適化**
   - LRUの閾値調整
   - ホットキャッシュ/コールドキャッシュの分離

---

## まとめ

v0.4.0のキャッシュシステムにより、以下を実現：

- ✅ ファイル変更に自動対応
- ✅ ファイル削除・移動に自動対応
- ✅ パフォーマンス大幅向上
- ✅ メモリ使用量の削減
- ✅ ユーザーが意識する必要なし

---

**Document Version**: 2.0 (実装完了版)
**Last Updated**: 2025-10-11
**Status**: ✅ 実装完了（v0.4.2）
