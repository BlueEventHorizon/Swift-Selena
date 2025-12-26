//
//  FileCacheEntry.swift
//  SwiftMCPServer
//
//  Created by k_terada on 2025/10/04.
//

import Foundation

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

    /// キャッシュの有効性チェック
    func isValid(currentModifiedDate: Date) -> Bool {
        return currentModifiedDate <= lastModified
    }

    /// アクセス時刻を更新（LRU用）
    mutating func updateAccessTime() {
        lastAccessed = Date()
    }
}

// MARK: - Cache Data Types

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
