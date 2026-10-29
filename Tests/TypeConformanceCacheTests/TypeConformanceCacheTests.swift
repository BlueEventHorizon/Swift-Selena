//
//  TypeConformanceCacheTests.swift
//  SwiftMCPServerTests
//
//  Created by k_terada on 2026/10/29.
//
//  [Code Header Format]
//
//  目的
//  - 型準拠キャッシュがファイルの変更・追加・削除に追従することを検証する
//  - Import キャッシュの無効化がシンボルキャッシュの更新に引きずられないことを検証する
//  - 「空のときしか構築されない」「他キャッシュの fileIndex に相乗りする」旧実装への回帰を防ぐ
//
//  主要機能
//  - 一時プロジェクトに Swift fixture を配置し SwiftSyntaxAnalyzer.getTypeHierarchy を直接呼び出す
//  - ファイルの更新時刻を未来にずらして「変更あり」を確実に再現する
//  - ProjectMemory のキャッシュ API を直接呼び、無効化の独立性を検証する
//
//  含まれる型
//  - TypeConformanceCacheTests: XCTestCase
//
//  関連型
//  - SwiftSyntaxAnalyzer, ProjectMemory, FileSearcher, TypeConformanceVisitor
//

import XCTest
import Foundation
import Logging
@testable import Swift_Selena

/// 型の関係は protocol 準拠（`conformingTypes`）で検証する。
/// TypeConformanceVisitor はプロジェクト内で定義された class を継承句から superclass と判定できない
/// （未知の名前は安全側に倒して protocol 扱い）ため、`subclasses` はこのテストの対象にしない。
final class TypeConformanceCacheTests: XCTestCase {

    // MARK: - テストフィクスチャ

    private var tempProjectDir: URL!
    private var clientId: String!
    private var projectMemory: ProjectMemory!
    private var savedClientIdEnv: String?
    private let logger = Logger(label: "TypeConformanceCacheTests")

    override func setUp() async throws {
        try await super.setUp()

        // 既存の MCP_CLIENT_ID を保存（tearDown で復元するため）
        if let prev = getenv("MCP_CLIENT_ID") {
            savedClientIdEnv = String(cString: prev)
        } else {
            savedClientIdEnv = nil
        }

        // クライアント ID を UUID で一意化（ProjectMemory のキャッシュを衝突させない）
        clientId = UUID().uuidString
        setenv("MCP_CLIENT_ID", clientId, 1)

        // 一時プロジェクトディレクトリを作成
        tempProjectDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("type_conformance_cache_tests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempProjectDir,
            withIntermediateDirectories: true
        )

        // 初期 fixture: protocol Marker と、それに準拠する Child1
        try write(
            fileName: "Models.swift",
            content: """
            import Foundation

            protocol Marker {}
            class Base {}
            class Child1: Marker {}
            """
        )

        // ProjectMemory を生成（環境変数 MCP_CLIENT_ID に従ってキャッシュ先が分離される）
        projectMemory = try ProjectMemory(projectPath: tempProjectDir.path)
    }

    override func tearDown() async throws {
        if let dir = tempProjectDir {
            try? FileManager.default.removeItem(at: dir)
        }

        // ProjectMemory のキャッシュ（~/.swift-selena/clients/{uuid}/）を削除
        if let id = clientId {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            let clientDir = homeDir
                .appendingPathComponent(AppConstants.storageDirectory)
                .appendingPathComponent("clients")
                .appendingPathComponent(id)
            try? FileManager.default.removeItem(at: clientDir)
        }

        // MCP_CLIENT_ID を save-then-restore
        if let prev = savedClientIdEnv {
            setenv("MCP_CLIENT_ID", prev, 1)
        } else {
            unsetenv("MCP_CLIENT_ID")
        }

        try await super.tearDown()
    }

    // MARK: - ヘルパー

    private func path(_ fileName: String) -> String {
        tempProjectDir.appendingPathComponent(fileName).path
    }

    /// fixture を書き出す。既存ファイルの上書き時は更新時刻を未来へずらし、
    /// ファイルシステムの時刻分解能に関係なく「変更あり」と判定されるようにする
    private func write(fileName: String, content: String) throws {
        let filePath = path(fileName)
        let existed = FileManager.default.fileExists(atPath: filePath)
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
        if existed {
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(10)],
                ofItemAtPath: filePath
            )
        }
    }

    private func hierarchy(
        of typeName: String,
        using memory: ProjectMemory? = nil
    ) async throws -> SwiftSyntaxAnalyzer.TypeHierarchy? {
        try await SwiftSyntaxAnalyzer.getTypeHierarchy(
            typeName: typeName,
            projectPath: tempProjectDir.path,
            projectMemory: memory ?? projectMemory,
            logger: logger
        )
    }

    // MARK: - 型準拠キャッシュ: ファイル変更への追従

    /// 初回呼び出しでキャッシュが構築され、階層が返る
    func test_getTypeHierarchy_buildsCacheOnFirstCall() async throws {
        let marker = try await hierarchy(of: "Marker")
        XCTAssertEqual(marker?.typeKind, "Protocol")
        XCTAssertEqual(marker?.conformingTypes, ["Child1"])

        let classDefinitions = await projectMemory.getClassDefinitions()
        XCTAssertEqual(classDefinitions, ["Base", "Child1"])
    }

    /// 既存ファイルに準拠型を追加すると、次の呼び出しで反映される（旧実装: 空でないため再構築されなかった）
    func test_getTypeHierarchy_reflectsAddedTypeAfterFileChange() async throws {
        _ = try await hierarchy(of: "Marker")

        try write(
            fileName: "Models.swift",
            content: """
            import Foundation

            protocol Marker {}
            class Base {}
            class Child1: Marker {}
            class Child2: Marker {}
            """
        )

        let marker = try await hierarchy(of: "Marker")
        XCTAssertEqual(marker?.conformingTypes, ["Child1", "Child2"], "変更後のファイルが再解析され準拠型が追加される")

        let child2 = try await hierarchy(of: "Child2")
        XCTAssertEqual(child2?.protocols, ["Marker"], "変更後に追加された型も見つかる")
    }

    /// ファイルから型を削除すると、その型は見つからなくなり、protocol の conformingTypes からも消える
    func test_getTypeHierarchy_dropsRemovedType() async throws {
        _ = try await hierarchy(of: "Child1")

        try write(
            fileName: "Models.swift",
            content: """
            import Foundation

            protocol Marker {}
            class Base {}
            """
        )

        let child1 = try await hierarchy(of: "Child1")
        XCTAssertNil(child1, "削除された型は見つからない")

        let marker = try await hierarchy(of: "Marker")
        XCTAssertEqual(marker?.conformingTypes, [], "削除された型は conformingTypes にも残らない")

        let classDefinitions = await projectMemory.getClassDefinitions()
        XCTAssertEqual(classDefinitions, ["Base"], "classDefinitions も作り直される")
    }

    /// 変更したファイル内の型は、「見つからない」ではなく再解析した最新の情報で返る（旧実装: nil を返していた）
    func test_getTypeHierarchy_returnsUpdatedInfoForTypeInChangedFile() async throws {
        let before = try await hierarchy(of: "Child1")
        XCTAssertEqual(before?.protocols, ["Marker"])

        try write(
            fileName: "Models.swift",
            content: """
            import Foundation

            protocol Marker {}
            class Base {}
            class Child1: Marker, Sendable {}
            """
        )

        let after = try await hierarchy(of: "Child1")
        XCTAssertNotNil(after, "変更されたファイル内の型も再解析されて見つかる")
        XCTAssertEqual(after?.protocols, ["Marker", "Sendable"])
    }

    // MARK: - 型準拠キャッシュ: ファイル追加・削除への追従

    /// 新しいファイルを追加すると、その中の型が反映される
    func test_getTypeHierarchy_picksUpNewFile() async throws {
        _ = try await hierarchy(of: "Marker")

        try write(
            fileName: "Extra.swift",
            content: """
            class Extra: Marker {}
            """
        )

        let marker = try await hierarchy(of: "Marker")
        XCTAssertEqual(marker?.conformingTypes, ["Child1", "Extra"], "追加されたファイル内の型が反映される")
    }

    /// ファイルを削除すると、その中の型がキャッシュから消える
    func test_getTypeHierarchy_dropsTypesFromDeletedFile() async throws {
        try write(
            fileName: "Extra.swift",
            content: """
            class Extra: Marker {}
            """
        )
        let before = try await hierarchy(of: "Marker")
        XCTAssertEqual(before?.conformingTypes, ["Child1", "Extra"])

        try FileManager.default.removeItem(atPath: path("Extra.swift"))

        let after = try await hierarchy(of: "Marker")
        XCTAssertEqual(after?.conformingTypes, ["Child1"], "削除されたファイル由来の型は消える")

        let extra = try await hierarchy(of: "Extra")
        XCTAssertNil(extra)
    }

    /// 変更がなければ再解析されず、キャッシュの内容がそのまま使われる
    func test_getTypeHierarchy_keepsCacheWhenNothingChanged() async throws {
        _ = try await hierarchy(of: "Marker")
        let stale = await projectMemory.isTypeConformanceCacheStale(filePath: path("Models.swift"))
        XCTAssertFalse(stale, "キャッシュ直後のファイルは stale ではない")

        let marker = try await hierarchy(of: "Marker")
        XCTAssertEqual(marker?.conformingTypes, ["Child1"])
    }

    // MARK: - Import キャッシュ: シンボルキャッシュからの独立

    /// シンボルの再キャッシュで fileIndex が更新されても、古い Import キャッシュは「最新」と誤判定されない
    /// （旧実装: Import キャッシュがシンボル用 fileIndex に相乗りしていたため、古い Import が返っていた）
    func test_importCache_isNotRevalidatedBySymbolCacheUpdate() async throws {
        let filePath = path("Models.swift")

        await projectMemory.cacheImports(
            filePath: filePath,
            imports: [.init(module: "Foundation", kind: nil, line: 1)]
        )
        let cachedBefore = await projectMemory.getCachedImports(filePath: filePath)
        XCTAssertEqual(cachedBefore?.map(\.module), ["Foundation"])

        // ファイルを変更し、シンボルだけ再キャッシュする（list_symbols 相当）
        try write(
            fileName: "Models.swift",
            content: """
            import Foundation
            import Combine

            class Base {}
            """
        )
        await projectMemory.cacheFileSymbols(
            filePath: filePath,
            symbols: [.init(name: "Base", kind: "Class", line: 4)]
        )

        let symbolsModified = await projectMemory.isFileModified(path: filePath)
        XCTAssertFalse(symbolsModified, "シンボルキャッシュは更新済みなので最新")

        let cachedAfter = await projectMemory.getCachedImports(filePath: filePath)
        XCTAssertNil(cachedAfter, "Import キャッシュは変更後に再キャッシュされていないので無効")

        // analyzeImports を通すと再解析されて最新になる
        let imports = try await SwiftSyntaxAnalyzer.analyzeImports(
            projectPath: tempProjectDir.path,
            projectMemory: projectMemory,
            logger: logger
        )
        XCTAssertEqual(imports[filePath]?.map(\.module).sorted(), ["Combine", "Foundation"])
    }

    // MARK: - 永続化

    /// 型準拠キャッシュとそのインデックスは memory.json に保存され、再ロード後も変更検知が働く
    func test_typeConformanceCache_survivesReloadAndStillDetectsChanges() async throws {
        _ = try await hierarchy(of: "Marker")

        let reloaded = try ProjectMemory(projectPath: tempProjectDir.path)
        let staleAfterReload = await reloaded.isTypeConformanceCacheStale(filePath: path("Models.swift"))
        XCTAssertFalse(staleAfterReload, "再ロード直後は stale ではない")

        try write(
            fileName: "Models.swift",
            content: """
            protocol Marker {}
            class Base {}
            class Child1: Marker {}
            class Child3: Marker {}
            """
        )
        let staleAfterChange = await reloaded.isTypeConformanceCacheStale(filePath: path("Models.swift"))
        XCTAssertTrue(staleAfterChange, "再ロード後でもファイル変更を検知する")

        let marker = try await hierarchy(of: "Marker", using: reloaded)
        XCTAssertEqual(marker?.conformingTypes, ["Child1", "Child3"])
    }
}
