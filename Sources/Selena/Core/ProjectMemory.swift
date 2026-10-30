//
//  ProjectMemory.swift
//  SwiftMCPServer
//
//  Created by k2moons on 2026/05/10.
//
//  [Code Header Format]
//
//  目的
//  - プロジェクト単位の解析結果・インデックス・ノートの永続キャッシュ管理
//  - SwiftSyntax / FileSearcher 等から再利用できる状態をディスクへ保存・復元
//  - DES-104 に準じたシンボルキャッシュスキーマ（v4）と cache_warning 伝達の土台
//
//  主要機能
//  - memory.json への Codable 永続化と cacheVersion による世代管理
//  - ファイル単位のシンボル・Import・型準拠キャッシュと変更検知による無効化
//  - デコード失敗時の空状態への復旧と cacheWarning フラグ設定（§8.2）
//
//  含まれる型
//  - ProjectMemory: プロジェクト単位の actor キャッシュ
//  - Memory および FileInfo / SymbolInfo / ImportInfo / TypeConformanceInfo / Note: 永続スナップショット
//
//  関連型
//  - CryptoKit（SHA256）, AppConstants
//

import Foundation
import CryptoKit

/// プロジェクトごとの永続化されたメモリ
actor ProjectMemory {
    let projectPath: String
    private let memoryDir: URL
    private let projectName: String
    
    /// キャッシュフォーマットのバージョン（構造変更時にインクリメント）
    ///
    /// v5 への bump 理由（2026/05/16）:
    /// - v4 リリース後に SymbolInfo へ parentScope / extensionTarget / moduleName を追加した経緯がある
    /// - 同一 cacheVersion 内でスキーマを拡張したため、3 フィールド時代に書かれた v4 キャッシュが温存され
    ///   新フィールドが nil で読み出される潜在不具合が発生していた
    /// - v5 に bump することで既存環境の旧フィールド欠落キャッシュを全破棄し再構築させる
    ///
    /// v6 への bump 理由（2026/10/29）:
    /// - Import / 型準拠キャッシュの無効化判定が、シンボルキャッシュ用の fileIndex に相乗りしていた。
    ///   そのため list_symbols 等でシンボルを再キャッシュして fileIndex が更新されると、
    ///   古い Import / 型準拠キャッシュが「最新」と誤判定されていた
    /// - 型準拠キャッシュは空のときしか構築されず、ファイル変更後に再構築されなかった
    /// - キャッシュ種別ごとの更新時刻インデックス（importFileIndex / typeFileIndex）を追加したためスキーマが変わる
    private static let cacheVersion = 6

    /// 全体をデコードする前に cacheVersion だけを読むための型
    /// （旧スキーマの全体デコード失敗を「破損」と誤認しないため）
    private struct VersionProbe: Codable {
        let cacheVersion: Int
    }

    struct Memory: Codable {
        var cacheVersion: Int
        var lastAnalyzed: Date
        var fileIndex: [String: FileInfo]            // シンボルキャッシュ用: ファイルパス -> 更新時刻
        var importFileIndex: [String: FileInfo]      // Import キャッシュ用: ファイルパス -> 更新時刻
        var typeFileIndex: [String: FileInfo]        // 型準拠キャッシュ用: ファイルパス -> 更新時刻
        var fileSymbolCache: [String: [SymbolInfo]]  // ファイルパス -> シンボル一覧
        var importCache: [String: [ImportInfo]]
        var typeConformanceCache: [String: TypeConformanceInfo]  // 型名 -> 型準拠情報（filePath を持つ）
        var classDefinitions: Set<String>  // プロジェクト内で定義されたClass名
        var notes: [Note]

        struct FileInfo: Codable {
            let path: String
            let lastModified: Date
        }

        /// v4: SymbolInfoV2 と同構成のキャッシュ永続化型（DES-104 §4.6 / §6.4）
        struct SymbolInfo: Codable {
            let name: String
            let kind: String
            let line: Int
            /// ネスト親の型名（ルート定義時は nil）
            let parentScope: String?
            /// extension 内定義時の対象型名（それ以外は nil）
            let extensionTarget: String?
            /// SwiftPM ターゲット名など（ベストエフォート、未取得時は nil）
            let moduleName: String?

            init(
                name: String,
                kind: String,
                line: Int,
                parentScope: String? = nil,
                extensionTarget: String? = nil,
                moduleName: String? = nil
            ) {
                self.name = name
                self.kind = kind
                self.line = line
                self.parentScope = parentScope
                self.extensionTarget = extensionTarget
                self.moduleName = moduleName
            }
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

    /// DES-104 §8.2: キャッシュ復旧が不完全だったことをツール応答へ伝えるためのフラグ
    private(set) var cacheWarning = false
    
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

        // actor の nonisolated init からは隔離メソッド（save）を呼べないため、
        // ローカル変数で確定させてから代入し、static ヘルパーで書き出す
        var loaded: Memory
        var warning = false
        var needsSave = false

        if FileManager.default.fileExists(atPath: memoryFile.path) {
            do {
                let data = try Data(contentsOf: memoryFile)

                // バージョンチェック: 古いバージョンなら全破棄・空再構築（§4.6、notes も含め部分復旧しない）
                // 旧スキーマはフィールド構成が異なり全体デコードに失敗しうるため、先に cacheVersion だけを読む
                let probe = try JSONDecoder().decode(VersionProbe.self, from: data)
                if probe.cacheVersion != Self.cacheVersion {
                    loaded = Self.createEmptyMemory()
                    needsSave = true
                } else {
                    loaded = try JSONDecoder().decode(Memory.self, from: data)
                }
            } catch {
                // §8.2: デコード失敗時は空メモリへ復旧し警告フラグを立てる（部分デコードによる notes 保持はしない）
                loaded = Self.createEmptyMemory()
                warning = true
                needsSave = true
            }
        } else {
            loaded = Self.createEmptyMemory()
            needsSave = true
        }

        if needsSave {
            try Self.write(&loaded, to: memoryFile)
        }
        self.memory = loaded
        self.cacheWarning = warning
    }

    /// DES-104 §8.2: 構造化結果の cache_warning 伝達用に外部から参照する
    func isCacheWarning() async -> Bool {
        cacheWarning
    }

    /// 空のメモリを作成
    private static func createEmptyMemory() -> Memory {
        Memory(
            cacheVersion: cacheVersion,
            lastAnalyzed: Date(),
            fileIndex: [:],
            importFileIndex: [:],
            typeFileIndex: [:],
            fileSymbolCache: [:],
            importCache: [:],
            typeConformanceCache: [:],
            classDefinitions: [],
            notes: []
        )
    }

    // MARK: - 更新時刻による無効化（キャッシュ種別ごとに独立したインデックスを持つ）

    /// ファイルの現在の更新時刻（取得できなければ nil）
    private static func modificationDate(of path: String) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    /// 指定インデックスの記録と比べてファイルが変更されたか（未記録・更新時刻の取得不可は変更扱い）
    private static func isModified(path: String, in index: [String: Memory.FileInfo]) -> Bool {
        guard let cached = index[path],
              let current = modificationDate(of: path) else {
            return true
        }
        return current > cached.lastModified
    }

    /// ファイルの現在の更新時刻を指定インデックスに記録する
    private static func record(path: String, in index: inout [String: Memory.FileInfo]) {
        if let date = modificationDate(of: path) {
            index[path] = Memory.FileInfo(path: path, lastModified: date)
        }
    }

    // MARK: - シンボルキャッシュ

    /// ファイルのシンボル一覧をキャッシュ（v4: 6 フィールド SymbolInfo）
    func cacheFileSymbols(filePath: String, symbols: [Memory.SymbolInfo]) {
        Self.record(path: filePath, in: &memory.fileIndex)
        memory.fileSymbolCache[filePath] = symbols
    }

    /// キャッシュからファイルのシンボル一覧を取得（v4: 6 フィールド SymbolInfo）
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

    /// シンボルキャッシュ時点からファイルが変更されたかチェック
    func isFileModified(path: String) -> Bool {
        Self.isModified(path: path, in: memory.fileIndex)
    }

    // MARK: - Import キャッシュ

    /// Import情報をキャッシュ
    func cacheImports(filePath: String, imports: [Memory.ImportInfo]) {
        Self.record(path: filePath, in: &memory.importFileIndex)
        memory.importCache[filePath] = imports
    }

    /// キャッシュからImport情報を取得（Import キャッシュ時点からファイルが変更されていれば nil）
    func getCachedImports(filePath: String) -> [Memory.ImportInfo]? {
        guard !Self.isModified(path: filePath, in: memory.importFileIndex) else {
            return nil
        }
        return memory.importCache[filePath]
    }

    /// 全Import情報を取得
    func getAllImports() -> [String: [Memory.ImportInfo]] {
        return memory.importCache
    }

    // MARK: - 型準拠キャッシュ

    /// ファイル単位で型準拠情報をキャッシュ（同じファイル由来の旧エントリは置き換える）
    func cacheTypeConformances(filePath: String, types: [Memory.TypeConformanceInfo]) {
        memory.typeConformanceCache = memory.typeConformanceCache.filter { $0.value.filePath != filePath }
        for typeInfo in types {
            memory.typeConformanceCache[typeInfo.typeName] = typeInfo
        }
        Self.record(path: filePath, in: &memory.typeFileIndex)
    }

    /// 型準拠キャッシュを更新する必要があるか（未キャッシュ、またはキャッシュ時点からファイルが変更された）
    func isTypeConformanceCacheStale(filePath: String) -> Bool {
        Self.isModified(path: filePath, in: memory.typeFileIndex)
    }

    /// 指定ファイル群に含まれないファイル由来の型準拠情報を削除する（削除したファイルの後始末）
    /// - Returns: 何かを削除したら true
    func pruneTypeConformances(keepingFiles files: Set<String>) -> Bool {
        let typeCountBefore = memory.typeConformanceCache.count
        let indexCountBefore = memory.typeFileIndex.count
        memory.typeConformanceCache = memory.typeConformanceCache.filter { files.contains($0.value.filePath) }
        memory.typeFileIndex = memory.typeFileIndex.filter { files.contains($0.key) }
        return memory.typeConformanceCache.count != typeCountBefore
            || memory.typeFileIndex.count != indexCountBefore
    }

    /// キャッシュから型情報を取得（型準拠キャッシュ時点からファイルが変更されていれば nil）
    func getCachedTypeConformance(typeName: String) -> Memory.TypeConformanceInfo? {
        guard let cached = memory.typeConformanceCache[typeName] else {
            return nil
        }
        guard !Self.isModified(path: cached.filePath, in: memory.typeFileIndex) else {
            return nil
        }
        return cached
    }

    /// 全型情報を取得
    func getAllTypeConformances() -> [String: Memory.TypeConformanceInfo] {
        return memory.typeConformanceCache
    }

    /// 型準拠キャッシュから Class 定義一覧を作り直す
    func rebuildClassDefinitions() {
        memory.classDefinitions = Set(
            memory.typeConformanceCache.values
                .filter { $0.typeKind == "Class" }
                .map(\.typeName)
        )
    }

    /// Class定義を取得
    func getClassDefinitions() -> Set<String> {
        return memory.classDefinitions
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
        try Self.write(&memory, to: memoryDir.appendingPathComponent("memory.json"))
    }

    /// Memory を JSON として書き出す（lastAnalyzed を更新する。init からも呼べるよう static）
    private static func write(_ memory: inout Memory, to file: URL) throws {
        memory.lastAnalyzed = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(memory)
        try data.write(to: file)
    }

    /// キャッシュをクリア
    func clearCache() throws {
        memory.fileSymbolCache.removeAll()
        memory.importCache.removeAll()
        memory.typeConformanceCache.removeAll()
        memory.classDefinitions.removeAll()
        memory.fileIndex.removeAll()
        memory.importFileIndex.removeAll()
        memory.typeFileIndex.removeAll()
        try save()
    }
}
