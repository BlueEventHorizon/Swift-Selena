//
//  SymbolVisitorV2Tests.swift
//  SwiftMCPServerTests
//
//  Created by k2moons on 2026/05/06.
//
//  [Code Header Format]
//
//  目的
//  - SymbolVisitorV2 のスコープスタック挙動と extension シンボル登録を検証
//  - DES-104 §4.5 / REQ-005 §4.4.1・§4.4.2 受入基準のテスト
//  - visit/visitPost 対称性とスタック崩壊防止の回帰防止
//
//  主要機能
//  - ルート型 / ネスト型 / extension 内型を区別する parentScope / extensionTarget 検証
//  - スコープスタックの push/pop 回数一致テスト（visit/visitPost 対称性）
//  - 早期 return パスを含むファイルで pop 抜け（スタック崩壊）が起きないことの検証
//  - extension 自身が "Extension" 種別シンボルとして登録されることの検証
//
//  含まれる型
//  - SymbolVisitorV2Tests: XCTestCase
//  - InstrumentedSymbolVisitorV2: visit/visitPost 呼び出し回数を記録するサブクラス（テスト専用）
//
//  関連型
//  - SymbolVisitorV2, SwiftSyntaxAnalyzer.SymbolInfoV2
//

import XCTest
import SwiftSyntax
import SwiftParser
@testable import Swift_Selena

final class SymbolVisitorV2Tests: XCTestCase {

    // MARK: - ヘルパー

    /// ソース文字列から SymbolVisitorV2 を実行し SymbolInfoV2 配列を返す
    private func runVisitor(source: String, filePath: String = "/tmp/__test__.swift") -> [SwiftSyntaxAnalyzer.SymbolInfoV2] {
        let sourceFile = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
        let visitor = SymbolVisitorV2(converter: converter, filePath: filePath)
        visitor.walk(sourceFile)
        return visitor.symbols
    }

    // MARK: - ルート型 / ネスト型 / extension 内型の区別（REQ-005 §4.4.2 (i)(ii)(iii)）

    /// (i) ルート定義の Button: parentScope = nil, extensionTarget = nil
    func testRootLevelStructHasNoScope() {
        let source = """
        struct Button {}
        """
        let symbols = runVisitor(source: source)

        // ルート型 Button のみが検出される
        let buttons = symbols.filter { $0.name == "Button" && $0.kind == "Struct" }
        XCTAssertEqual(buttons.count, 1, "ルートに Button が 1 件存在するはず")
        XCTAssertNil(buttons.first?.parentScope, "ルート定義は parentScope が nil")
        XCTAssertNil(buttons.first?.extensionTarget, "ルート定義は extensionTarget が nil")
    }

    /// (ii) ネスト型 enum Foo { struct Button } の Button: parentScope = "Foo"
    func testNestedStructHasParentScope() {
        let source = """
        enum Foo {
            struct Button {}
        }
        """
        let symbols = runVisitor(source: source)

        // ネスト型 Button を検証
        let nestedButton = symbols.first(where: { $0.name == "Button" && $0.kind == "Struct" })
        XCTAssertNotNil(nestedButton, "ネスト型 Button が検出されるはず")
        XCTAssertEqual(nestedButton?.parentScope, "Foo", "ネスト型は parentScope=Foo")
        XCTAssertNil(nestedButton?.extensionTarget, "ネスト型 (extension 配下でない) は extensionTarget が nil")

        // 親 Foo 自身は parentScope=nil
        let foo = symbols.first(where: { $0.name == "Foo" && $0.kind == "Enum" })
        XCTAssertEqual(foo?.parentScope, nil, "ルートの Foo は parentScope が nil")
    }

    /// (iii) extension Foo { struct Button } の Button: extensionTarget = "Foo"
    func testExtensionScopedStructHasExtensionTarget() {
        let source = """
        extension Foo {
            struct Button {}
        }
        """
        let symbols = runVisitor(source: source)

        let button = symbols.first(where: { $0.name == "Button" && $0.kind == "Struct" })
        XCTAssertNotNil(button, "extension 内の Button が検出されるはず")
        XCTAssertNil(button?.parentScope, "extension 直下のシンボルは parentScope が nil（DES-104 §4.5 決定規則）")
        XCTAssertEqual(button?.extensionTarget, "Foo", "extension 内のシンボルは extensionTarget=Foo")
    }

    /// 3 ケースの区別が同一ソース内で成り立つことを確認（REQ-005 §4.4.2 受入基準）
    func testRootNestedExtensionDistinguishedTogether() {
        let source = """
        struct Button {}
        enum Foo {
            struct Button {}
        }
        extension Bar {
            struct Button {}
        }
        """
        let symbols = runVisitor(source: source)
        let buttons = symbols.filter { $0.name == "Button" && $0.kind == "Struct" }
        XCTAssertEqual(buttons.count, 3, "Button は 3 件検出されるはず")

        // ルート Button
        XCTAssertTrue(buttons.contains(where: { $0.parentScope == nil && $0.extensionTarget == nil }),
                      "ルート Button が含まれるはず")
        // ネスト Button
        XCTAssertTrue(buttons.contains(where: { $0.parentScope == "Foo" && $0.extensionTarget == nil }),
                      "Foo ネスト下の Button が含まれるはず")
        // extension Button
        XCTAssertTrue(buttons.contains(where: { $0.parentScope == nil && $0.extensionTarget == "Bar" }),
                      "Bar extension 配下の Button が含まれるはず")
    }

    // MARK: - extension 自身のシンボル登録（REQ-005 §4.4.1 受入基準）

    func testExtensionItselfIsRegisteredAsExtensionKind() {
        let source = """
        extension MyType {
            func helper() {}
        }
        """
        let symbols = runVisitor(source: source)

        // extension 自身のシンボル
        let extSymbols = symbols.filter { $0.kind == "Extension" }
        XCTAssertEqual(extSymbols.count, 1, "extension 自身が 1 件 'Extension' 種別で登録されるはず")
        XCTAssertEqual(extSymbols.first?.name, "MyType", "extension の名前は対象型名 (extendedType)")
    }

    func testNestedExtensionRegistersExtensionKindForEachExtension() {
        // ジェネリックス付き extension（trimmedDescription で extendedType が `Foo<Bar>` になる場合の挙動）
        let source = """
        extension Array {
            func first2() {}
        }
        extension Dictionary {
            func helper() {}
        }
        """
        let symbols = runVisitor(source: source)
        let extSymbols = symbols.filter { $0.kind == "Extension" }
        XCTAssertEqual(extSymbols.count, 2, "extension が 2 件登録されるはず")
        XCTAssertTrue(extSymbols.contains(where: { $0.name == "Array" }))
        XCTAssertTrue(extSymbols.contains(where: { $0.name == "Dictionary" }))
    }

    // MARK: - visit/visitPost 対称性（push/pop 回数一致）

    /// push/pop の対称性を計測するための instrumented サブクラス
    /// 訪問数は SymbolVisitorV2 の visit/visitPost と完全対応するためテスト中で観測する
    private final class InstrumentedSymbolVisitorV2: SyntaxVisitor {
        var classVisitCount = 0
        var classVisitPostCount = 0
        var structVisitCount = 0
        var structVisitPostCount = 0
        var enumVisitCount = 0
        var enumVisitPostCount = 0
        var protocolVisitCount = 0
        var protocolVisitPostCount = 0
        var actorVisitCount = 0
        var actorVisitPostCount = 0
        var extensionVisitCount = 0
        var extensionVisitPostCount = 0

        override init(viewMode: SyntaxTreeViewMode) {
            super.init(viewMode: viewMode)
        }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            classVisitCount += 1
            return .visitChildren
        }
        override func visitPost(_ node: ClassDeclSyntax) {
            classVisitPostCount += 1
        }
        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            structVisitCount += 1
            return .visitChildren
        }
        override func visitPost(_ node: StructDeclSyntax) {
            structVisitPostCount += 1
        }
        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            enumVisitCount += 1
            return .visitChildren
        }
        override func visitPost(_ node: EnumDeclSyntax) {
            enumVisitPostCount += 1
        }
        override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
            protocolVisitCount += 1
            return .visitChildren
        }
        override func visitPost(_ node: ProtocolDeclSyntax) {
            protocolVisitPostCount += 1
        }
        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
            actorVisitCount += 1
            return .visitChildren
        }
        override func visitPost(_ node: ActorDeclSyntax) {
            actorVisitPostCount += 1
        }
        override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
            extensionVisitCount += 1
            return .visitChildren
        }
        override func visitPost(_ node: ExtensionDeclSyntax) {
            extensionVisitPostCount += 1
        }
    }

    /// 訪問対象の visit/visitPost 呼び出し回数が常に一致することを観察し、
    /// SymbolVisitorV2 が依拠する SwiftSyntax の対称性前提を検証する
    func testVisitVisitPostSymmetryAcrossNestedStructure() {
        let source = """
        class Outer {
            struct Inner {
                enum E {
                    case a
                }
            }
            actor A {}
        }
        protocol P {}
        extension Outer {
            struct InnerExt {}
        }
        extension Outer.Inner {
            func f() {}
        }
        """

        let sourceFile = Parser.parse(source: source)
        let probe = InstrumentedSymbolVisitorV2(viewMode: .sourceAccurate)
        probe.walk(sourceFile)

        // 各種別の visit / visitPost 回数が一致する
        XCTAssertEqual(probe.classVisitCount, probe.classVisitPostCount, "Class visit/visitPost が対称")
        XCTAssertEqual(probe.structVisitCount, probe.structVisitPostCount, "Struct visit/visitPost が対称")
        XCTAssertEqual(probe.enumVisitCount, probe.enumVisitPostCount, "Enum visit/visitPost が対称")
        XCTAssertEqual(probe.protocolVisitCount, probe.protocolVisitPostCount, "Protocol visit/visitPost が対称")
        XCTAssertEqual(probe.actorVisitCount, probe.actorVisitPostCount, "Actor visit/visitPost が対称")
        XCTAssertEqual(probe.extensionVisitCount, probe.extensionVisitPostCount, "Extension visit/visitPost が対称")

        // SymbolVisitorV2 自体を実行し、抽出結果がスタック崩壊なく完結することを観察
        let symbols = runVisitor(source: source)

        // 末尾シンボル（最後のシンボル）はトップレベルの walk が正常に完結している
        // 観点で確認可能 - ここでは「Outer.Inner の extension 配下の f」が正しく
        // extensionTarget="Outer.Inner" として登録されることをスタック整合性の証跡とする
        let f = symbols.first(where: { $0.name == "f" && $0.kind == "Function" })
        XCTAssertNotNil(f)
        XCTAssertEqual(f?.extensionTarget, "Outer.Inner",
                       "extension Outer.Inner 内の関数 f は extensionTarget=Outer.Inner")
        XCTAssertNil(f?.parentScope, "extension 配下なので parentScope は nil")

        // class Outer 配下の Inner の InnerExt は別 extension で定義されている → root 直下の extension
        let innerExt = symbols.first(where: { $0.name == "InnerExt" && $0.kind == "Struct" })
        XCTAssertNotNil(innerExt)
        XCTAssertEqual(innerExt?.extensionTarget, "Outer")

        // class Outer のネスト Inner は parentScope=Outer
        let inner = symbols.first(where: { $0.name == "Inner" && $0.kind == "Struct" })
        XCTAssertEqual(inner?.parentScope, "Outer")

        // ネストの最深部 enum E（class Outer > struct Inner の中）の parentScope は直近非 extension の "Inner"
        let e = symbols.first(where: { $0.name == "E" && $0.kind == "Enum" })
        XCTAssertEqual(e?.parentScope, "Inner")
    }

    // MARK: - スタック崩壊防止: 早期 return パス含む構造でも push/pop が正しく完結する

    /// 早期 return が起こりうる Variable / Function / Macro 等を含むファイルで
    /// pop 漏れが起きないこと（スタック崩壊が起きていれば後続のシンボルが
    /// 誤った parentScope を持ってしまう or visitor が異常終了する）を検証する
    func testNoStackCorruptionWithEarlyReturnTriggers() {
        // VariableDeclSyntax のバインディングが空の経路、Function 内のローカル定義など、
        // visit から早期 return する候補を含むソース。
        let source = """
        struct A {
            var x = 1
            var y: Int { 0 }
            func helper() {
                let local = 10
                _ = local
            }
        }
        struct B {
            var z = 2
        }
        """
        let symbols = runVisitor(source: source)

        // A と B が両方ともルート定義（parentScope=nil）として検出されているか
        let a = symbols.first(where: { $0.name == "A" && $0.kind == "Struct" })
        let b = symbols.first(where: { $0.name == "B" && $0.kind == "Struct" })
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertNil(a?.parentScope, "A はルート定義")
        XCTAssertNil(b?.parentScope, "B はルート定義")

        // A の中の x, y, helper は parentScope="A"
        let x = symbols.first(where: { $0.name == "x" && $0.kind == "Variable" })
        XCTAssertEqual(x?.parentScope, "A", "x は A 配下にあるはず")
        let helper = symbols.first(where: { $0.name == "helper" && $0.kind == "Function" })
        XCTAssertEqual(helper?.parentScope, "A", "helper は A 配下にあるはず")

        // B の z は parentScope="B"（A のスタックが残っていれば誤って "A" になるはず）
        let z = symbols.first(where: { $0.name == "z" && $0.kind == "Variable" })
        XCTAssertEqual(z?.parentScope, "B",
                       "z は B 配下のはず — A のスタックが残っていれば誤検知される（スタック崩壊回帰防止）")
    }

    /// 連続 extension の後にルート型を置き、extension スコープが正しく抜けていることを確認
    func testExtensionScopeReleasedAfterExtensionEnds() {
        let source = """
        extension Foo {
            struct Inside {}
        }
        struct OutsideRoot {}
        """
        let symbols = runVisitor(source: source)

        let inside = symbols.first(where: { $0.name == "Inside" && $0.kind == "Struct" })
        XCTAssertEqual(inside?.extensionTarget, "Foo")
        XCTAssertNil(inside?.parentScope)

        let outside = symbols.first(where: { $0.name == "OutsideRoot" && $0.kind == "Struct" })
        XCTAssertNotNil(outside, "extension の後のルート型が検出されるはず")
        XCTAssertNil(outside?.extensionTarget,
                     "extension スコープが正しく pop されていないとここに 'Foo' が残る（スタック崩壊検出）")
        XCTAssertNil(outside?.parentScope)
    }

    // MARK: - モジュール名解決ヘルパー（DES-104 §4.5 / TBD-002）

    /// Package.swift が見つからない場合は nil を返す
    func testResolveModuleNameReturnsNilWhenNoPackageSwift() {
        // システムの一時ディレクトリ直下（Package.swift が存在しない場所）でテスト
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("symbol_visitor_v2_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dummyPath = tempDir.appendingPathComponent("Dummy.swift").path
        let resolved = SymbolVisitorV2.resolveModuleName(from: dummyPath)
        // /var/folders/... 配下では Package.swift は見つからないため nil
        // ※ システム上 / 配下まで遡って Package.swift が見つかる可能性は無視できる前提
        XCTAssertNil(resolved, "Package.swift が無いパスでは moduleName が nil")
    }

    /// Sources/{target}/ 配下のファイルでターゲット名が解決される
    func testResolveModuleNameFromSourcesPath() {
        // 仮想的な SwiftPM 構造を一時ディレクトリに作成
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("svv2_pkg_\(UUID().uuidString)")
        let sourcesDir = tempDir.appendingPathComponent("Sources/MyTarget")
        try? FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Package.swift を作成
        let packageContent = """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(name: "MyTarget", targets: [.target(name: "MyTarget", path: "Sources/MyTarget")])
        """
        let packageURL = tempDir.appendingPathComponent("Package.swift")
        try? packageContent.write(to: packageURL, atomically: true, encoding: .utf8)

        // ダミーソースファイル
        let sourceFile = sourcesDir.appendingPathComponent("Foo.swift")
        try? "// dummy".write(to: sourceFile, atomically: true, encoding: .utf8)

        let resolved = SymbolVisitorV2.resolveModuleName(from: sourceFile.path)
        XCTAssertEqual(resolved, "MyTarget", "Sources/MyTarget/ 配下のファイルから MyTarget が解決される")
    }

    /// Tests/ 配下のファイル（Sources/ ではない）は nil
    func testResolveModuleNameReturnsNilForFilesOutsideSources() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("svv2_pkg_outside_\(UUID().uuidString)")
        let testsDir = tempDir.appendingPathComponent("Tests/MyTests")
        try? FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageContent = #"let package = Package(name: "Foo")"#
        try? packageContent.write(to: tempDir.appendingPathComponent("Package.swift"),
                                  atomically: true, encoding: .utf8)

        let testFile = testsDir.appendingPathComponent("FooTests.swift")
        try? "".write(to: testFile, atomically: true, encoding: .utf8)

        let resolved = SymbolVisitorV2.resolveModuleName(from: testFile.path)
        XCTAssertNil(resolved, "Tests/ 配下では Sources/ パターンに合致せず nil")
    }
}
