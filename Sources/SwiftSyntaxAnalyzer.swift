//
//  SwiftSyntaxAnalyzer.swift
//  SwiftMCPServer
//
//  Created by k_terada on 2025/10/03.
//

import Foundation
import SwiftSyntax
import SwiftParser

/// SwiftSyntax静的解析のエントリポイント
enum SwiftSyntaxAnalyzer {
    // MARK: - Data Structures

    struct SymbolInfo {
        let name: String
        let kind: String
        let line: Int
    }

    struct PropertyWrapperInfo {
        let propertyName: String
        let wrapperType: String
        let typeName: String?
        let line: Int
    }

    struct TypeConformanceInfo {
        let typeName: String
        let typeKind: String  // Class, Struct, Enum, Actor
        let protocols: [String]
        let superclass: String?
        let line: Int
    }

    struct ExtensionInfo {
        let extendedType: String
        let protocols: [String]
        let line: Int
        let members: [MemberInfo]

        struct MemberInfo {
            let name: String
            let kind: String  // Function, Variable, etc.
            let line: Int
        }
    }

    struct ImportInfo {
        let module: String
        let kind: String?  // typealias, struct, class, func, var, let, etc.
        let symbols: [String]  // specific symbols if any
        let line: Int
    }

    // MARK: - Public Methods

    /// ファイル内の全シンボルを抽出
    static func listSymbols(filePath: String) throws -> [SymbolInfo] {
        let content = try String(contentsOfFile: filePath)
        let sourceFile = Parser.parse(source: content)

        let visitor = SymbolVisitor(converter: SourceLocationConverter(fileName: filePath, tree: sourceFile))
        visitor.walk(sourceFile)

        return visitor.symbols
    }

    /// SwiftUI Property Wrapperを抽出
    static func listPropertyWrappers(filePath: String) throws -> [PropertyWrapperInfo] {
        let content = try String(contentsOfFile: filePath)
        let sourceFile = Parser.parse(source: content)

        let visitor = PropertyWrapperVisitor(converter: SourceLocationConverter(fileName: filePath, tree: sourceFile))
        visitor.walk(sourceFile)

        return visitor.propertyWrappers
    }

    /// Protocol準拠と継承関係を抽出
    static func listTypeConformances(filePath: String) throws -> [TypeConformanceInfo] {
        let content = try String(contentsOfFile: filePath)
        let sourceFile = Parser.parse(source: content)

        let visitor = TypeConformanceVisitor(converter: SourceLocationConverter(fileName: filePath, tree: sourceFile))
        visitor.walk(sourceFile)

        return visitor.typeConformances
    }

    /// Extensionを抽出
    static func listExtensions(filePath: String) throws -> [ExtensionInfo] {
        let content = try String(contentsOfFile: filePath)
        let sourceFile = Parser.parse(source: content)

        let visitor = ExtensionVisitor(converter: SourceLocationConverter(fileName: filePath, tree: sourceFile))
        visitor.walk(sourceFile)

        return visitor.extensions
    }

    /// Import文を抽出
    static func listImports(filePath: String) throws -> [ImportInfo] {
        let content = try String(contentsOfFile: filePath)
        let sourceFile = Parser.parse(source: content)

        let visitor = ImportVisitor(converter: SourceLocationConverter(fileName: filePath, tree: sourceFile))
        visitor.walk(sourceFile)

        return visitor.imports
    }

    /// プロジェクト全体のImport依存関係を解析（キャッシュ利用）
    static func analyzeImports(projectPath: String, projectMemory: ProjectMemory) throws -> [String: [ImportInfo]] {
        let swiftFiles = try FileSearcher.findFiles(in: projectPath, pattern: "*.swift")

        var fileImports: [String: [ImportInfo]] = [:]

        for file in swiftFiles {
            // キャッシュから取得を試みる
            if let cached = projectMemory.getCachedImports(filePath: file) {
                let imports = cached.map { ImportInfo(module: $0.module, kind: $0.kind, symbols: [], line: $0.line) }
                fileImports[file] = imports
                continue
            }

            // キャッシュになければ解析
            do {
                let imports = try listImports(filePath: file)
                if !imports.isEmpty {
                    fileImports[file] = imports

                    // キャッシュに保存
                    let cacheData = imports.map { ProjectMemory.Memory.ImportInfo(module: $0.module, kind: $0.kind, line: $0.line) }
                    projectMemory.cacheImports(filePath: file, imports: cacheData)
                }
            } catch {
                // ファイル読み込みエラーをスキップ
                continue
            }
        }

        // メモリを保存
        try? projectMemory.save()

        return fileImports
    }
}
