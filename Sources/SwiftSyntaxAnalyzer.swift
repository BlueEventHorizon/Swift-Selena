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

    struct TypeHierarchy {
        let typeName: String
        let typeKind: String
        let filePath: String
        let line: Int
        let superclass: String?
        let protocols: [String]
        let subclasses: [String]
        let conformingTypes: [String]  // Protocol conforming types (if this is a Protocol)
    }

    struct XCTestInfo {
        let className: String
        let filePath: String
        let line: Int
        let testMethods: [TestMethod]

        struct TestMethod {
            let name: String
            let line: Int
        }
    }

    struct TypeUsageInfo {
        let typeName: String
        let usageKind: String  // Variable, Parameter, ReturnType, PropertyType
        let context: String    // 使用されているコンテキスト（関数名、変数名等）
        let filePath: String
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

    /// 型の継承階層を取得（キャッシュ利用）
    static func getTypeHierarchy(typeName: String, projectPath: String, projectMemory: ProjectMemory) throws -> TypeHierarchy? {
        // キャッシュを構築（必要な場合のみ）
        if projectMemory.getAllTypeConformances().isEmpty {
            try buildTypeConformanceCache(projectPath: projectPath, projectMemory: projectMemory)
        }

        // キャッシュから型情報を取得
        guard let cachedType = projectMemory.getCachedTypeConformance(typeName: typeName) else {
            return nil
        }

        let allTypes = projectMemory.getAllTypeConformances()

        // サブクラスを検索
        var subclasses: [String] = []
        for (name, typeInfo) in allTypes {
            if typeInfo.superclass == typeName {
                subclasses.append(name)
            }
        }

        // Protocol準拠型を検索
        var conformingTypes: [String] = []
        if cachedType.typeKind == "Protocol" {
            for (name, typeInfo) in allTypes {
                if typeInfo.protocols.contains(typeName) {
                    conformingTypes.append(name)
                }
            }
        }

        return TypeHierarchy(
            typeName: typeName,
            typeKind: cachedType.typeKind,
            filePath: cachedType.filePath,
            line: cachedType.line,
            superclass: cachedType.superclass,
            protocols: cachedType.protocols,
            subclasses: subclasses.sorted(),
            conformingTypes: conformingTypes.sorted()
        )
    }

    /// 型情報キャッシュを構築
    private static func buildTypeConformanceCache(projectPath: String, projectMemory: ProjectMemory) throws {
        let swiftFiles = try FileSearcher.findFiles(in: projectPath, pattern: "*.swift")

        for file in swiftFiles {
            do {
                let conformances = try listTypeConformances(filePath: file)
                for conformance in conformances {
                    let cacheData = ProjectMemory.Memory.TypeConformanceInfo(
                        typeName: conformance.typeName,
                        typeKind: conformance.typeKind,
                        filePath: file,
                        line: conformance.line,
                        superclass: conformance.superclass,
                        protocols: conformance.protocols
                    )
                    projectMemory.cacheTypeConformance(typeName: conformance.typeName, typeInfo: cacheData)
                }
            } catch {
                // ファイル読み込みエラーをスキップ
                continue
            }
        }

        // メモリを保存
        try? projectMemory.save()
    }

    /// XCTestケースを検出
    static func findTestCases(projectPath: String) throws -> [XCTestInfo] {
        let swiftFiles = try FileSearcher.findFiles(in: projectPath, pattern: "*.swift")

        var testCases: [XCTestInfo] = []

        for file in swiftFiles {
            do {
                let content = try String(contentsOfFile: file)
                let sourceFile = Parser.parse(source: content)

                let visitor = XCTestVisitor(
                    converter: SourceLocationConverter(fileName: file, tree: sourceFile),
                    filePath: file
                )
                visitor.walk(sourceFile)

                testCases.append(contentsOf: visitor.testClasses)
            } catch {
                // ファイル読み込みエラーをスキップ
                continue
            }
        }

        return testCases
    }

    /// 型使用箇所を検出
    static func findTypeUsages(typeName: String, projectPath: String) throws -> [TypeUsageInfo] {
        let swiftFiles = try FileSearcher.findFiles(in: projectPath, pattern: "*.swift")

        var typeUsages: [TypeUsageInfo] = []

        for file in swiftFiles {
            do {
                let content = try String(contentsOfFile: file)
                let sourceFile = Parser.parse(source: content)

                let visitor = TypeUsageVisitor(
                    converter: SourceLocationConverter(fileName: file, tree: sourceFile),
                    filePath: file,
                    targetTypeName: typeName
                )
                visitor.walk(sourceFile)

                typeUsages.append(contentsOf: visitor.typeUsages)
            } catch {
                // ファイル読み込みエラーをスキップ
                continue
            }
        }

        return typeUsages
    }
}
