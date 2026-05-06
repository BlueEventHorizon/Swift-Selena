//
//  SwiftSyntaxAnalyzer.swift
//  SwiftMCPServer
//
//  Created by k2moons on 2025/10/03.
//
//  [Code Header Format]
//
//  目的
//  - SwiftSyntax を用いた静的解析の単一エントリポイント提供
//  - シンボル・型準拠・Import・Extension・テスト等の抽出 API を集約
//  - 解析結果のキャッシュ連携（ProjectMemory）と一貫した throws/skip 方針の整合
//
//  主要機能
//  - ファイル単位のシンボル抽出（既存: SymbolInfo / 拡張: SymbolInfoV2 によるスコープ情報付き）
//  - Property Wrapper / Type Conformance / Extension / Import の抽出
//  - プロジェクト横断の Import 依存関係および型階層の解析（キャッシュ利用）
//  - XCTest / Swift Testing のテスト検出
//
//  含まれる型
//  - SymbolInfo: シンボル名・種別・行番号の基本 3 フィールド（既存ツール互換用）
//  - SymbolInfoV2: 上記 3 フィールド + parentScope / extensionTarget / moduleName のスコープ情報拡張型
//  - PropertyWrapperInfo, TypeConformanceInfo, ExtensionInfo, ImportInfo, TypeHierarchy, XCTestInfo, SwiftTestInfo
//
//  関連型
//  - ProjectMemory（キャッシュ層）, SymbolVisitor 系（Visitors/）
//

import Foundation
import Logging
import SwiftSyntax
import SwiftParser

/// SwiftSyntax静的解析のエントリポイント
enum SwiftSyntaxAnalyzer {
    // MARK: - データ構造

    struct SymbolInfo {
        let name: String
        let kind: String
        let line: Int
    }

    /// スコープ情報付きシンボル情報（DES-104 §4.5）
    ///
    /// 既存 `SymbolInfo`（3 フィールド）を変更せず別型として並存させる（DES-104 §6.4 並存方針）。
    /// 同名シンボルの所属（ルート / ネスト型 / extension 内）を区別するための拡張フィールドを持つ。
    struct SymbolInfoV2 {
        /// シンボル名
        let name: String
        /// 表示用 kind 値（`Class` / `Struct` 等。SymbolVisitor 系の出力と同一表記）
        let kind: String
        /// 宣言開始行（1-indexed）
        let line: Int
        /// ネスト親の型名（例: `Foo.Button` の場合 `Foo`）。ルート定義時は nil
        let parentScope: String?
        /// extension 内定義時の対象型名（例: `extension Foo { struct Button }` の場合 `Foo`）。それ以外は nil
        let extensionTarget: String?
        /// SwiftPM ターゲット名（ベストエフォート、未取得時は nil）
        let moduleName: String?
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

    /// Swift Testing (@Test, @Suite) 情報
    struct SwiftTestInfo {
        let suiteName: String
        let suiteDisplayName: String
        let suiteKind: String  // Struct, Class, Enum
        let filePath: String
        let line: Int
        let hasSuiteAttribute: Bool
        let testMethods: [TestMethod]

        struct TestMethod {
            let name: String
            let displayName: String
            let line: Int
        }
    }

    // MARK: - 公開メソッド

    /// ファイル内の全シンボルを抽出
    static func listSymbols(filePath: String) throws -> [SymbolInfo] {
        let content = try String(contentsOfFile: filePath)
        let sourceFile = Parser.parse(source: content)

        let visitor = SymbolVisitor(converter: SourceLocationConverter(fileName: filePath, tree: sourceFile))
        visitor.walk(sourceFile)

        return visitor.symbols
    }

    /// ファイル内の全シンボルを所属スコープ情報付きで抽出（DES-104 §4.5 / §6.6）
    ///
    /// 既存 `listSymbols(filePath:)` と並存する API（DES-104 §6.4 並存方針）。
    /// パース失敗・I/O エラー時は throws し、呼び出し側（FindSymbolDefinitionTool 等）が
    /// catch して当該ファイルを skipped_files に列挙しつつループを継続する責務を持つ
    /// （DES-104 §8.4 / §6.6 シーケンス図参照）。
    ///
    /// - Parameter filePath: 解析対象 Swift ファイルの絶対パス
    /// - Returns: スコープ情報付きシンボル一覧。本タスク（TASK-005）ではスタブのため空配列を返す
    /// - Throws:
    ///   - **現スタブ段階（TASK-005）**: `String(contentsOfFile:)` による I/O エラーのみ伝播する。
    ///     SwiftSyntax のパースは行わないため、パースエラーは発生しない。
    ///   - **本体実装完成後（TASK-006）**: I/O エラーに加え、SwiftSyntax のパース失敗も伝播する想定。
    ///     呼び出し側でファイル単位のスキップを実装する API 契約は両段階で同一。
    ///
    /// TODO: ⚠️ SymbolVisitorV2 を用いた本体実装が未実装です（TASK-006 で実装予定）
    static func listSymbolsWithScope(filePath: String) throws -> [SymbolInfoV2] {
        // パース失敗時のスキップ挙動を呼び出し側が判定できるよう、
        // ファイル読み込みは listSymbols と同じく throws で伝播させる API 形状とする。
        // 本タスクではスタブとして空配列を返す（TASK-006 で SymbolVisitorV2 連携を実装）。
        _ = try String(contentsOfFile: filePath)
        return []
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
    static func analyzeImports(projectPath: String, projectMemory: ProjectMemory, logger: Logger? = nil) async throws -> [String: [ImportInfo]] {
        let swiftFiles = try FileSearcher.findFiles(in: projectPath, pattern: "*.swift")

        var fileImports: [String: [ImportInfo]] = [:]

        for file in swiftFiles {
            // キャッシュから取得を試みる
            if let cached = await projectMemory.getCachedImports(filePath: file) {
                let imports = cached.map { ImportInfo(module: $0.module, kind: $0.kind, symbols: [], line: $0.line) }
                fileImports[file] = imports
                continue
            }

            // キャッシュになければ解析
            do {
                let imports = try listImports(filePath: file)
                // v0.5.4: Importが空でも結果に含める（ファイル数を正確にカウント）
                fileImports[file] = imports

                // キャッシュに保存
                let cacheData = imports.map { ProjectMemory.Memory.ImportInfo(module: $0.module, kind: $0.kind, line: $0.line) }
                await projectMemory.cacheImports(filePath: file, imports: cacheData)
            } catch {
                // ファイル読み込みエラーをスキップ
                continue
            }
        }

        // メモリを保存（失敗しても解析結果は返す）
        do {
            try await projectMemory.save()
        } catch {
            logger?.warning("インポートキャッシュの保存に失敗: \(error)")
        }

        return fileImports
    }

    /// 型の継承階層を取得（キャッシュ利用）
    static func getTypeHierarchy(typeName: String, projectPath: String, projectMemory: ProjectMemory, logger: Logger? = nil) async throws -> TypeHierarchy? {
        // キャッシュを構築（必要な場合のみ）
        if await projectMemory.getAllTypeConformances().isEmpty {
            try await buildTypeConformanceCache(projectPath: projectPath, projectMemory: projectMemory, logger: logger)
        }

        // キャッシュから型情報を取得
        guard let cachedType = await projectMemory.getCachedTypeConformance(typeName: typeName) else {
            return nil
        }

        let allTypes = await projectMemory.getAllTypeConformances()

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
    private static func buildTypeConformanceCache(projectPath: String, projectMemory: ProjectMemory, logger: Logger? = nil) async throws {
        let swiftFiles = try FileSearcher.findFiles(in: projectPath, pattern: "*.swift")

        // Class定義をクリアして再収集
        await projectMemory.clearClassDefinitions()

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
                    await projectMemory.cacheTypeConformance(typeName: conformance.typeName, typeInfo: cacheData)

                    // Class定義を収集
                    if conformance.typeKind == "Class" {
                        await projectMemory.addClassDefinition(conformance.typeName)
                    }
                }
            } catch {
                // ファイル読み込みエラーをスキップ
                continue
            }
        }

        // メモリを保存（失敗しても解析結果は返す）
        do {
            try await projectMemory.save()
        } catch {
            logger?.warning("型準拠キャッシュの保存に失敗: \(error)")
        }
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

    /// Swift Testingテストを検出（@Test, @Suite）
    static func findSwiftTests(projectPath: String) throws -> [SwiftTestInfo] {
        let swiftFiles = try FileSearcher.findFiles(in: projectPath, pattern: "*.swift")

        var testSuites: [SwiftTestInfo] = []

        for file in swiftFiles {
            do {
                let content = try String(contentsOfFile: file)
                let sourceFile = Parser.parse(source: content)

                let visitor = SwiftTestingVisitor(
                    converter: SourceLocationConverter(fileName: file, tree: sourceFile),
                    filePath: file
                )
                visitor.walk(sourceFile)

                testSuites.append(contentsOf: visitor.testSuites)
            } catch {
                // ファイル読み込みエラーをスキップ
                continue
            }
        }

        return testSuites
    }
}
