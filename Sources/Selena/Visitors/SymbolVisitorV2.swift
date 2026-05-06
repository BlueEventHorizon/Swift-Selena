//
//  SymbolVisitorV2.swift
//  SwiftMCPServer
//
//  Created by k2moons on 2026/05/06.
//
//  [Code Header Format]
//
//  目的
//  - DES-104 §4.5 / REQ-005 §4.4.2 に基づくスコープ情報付きシンボル抽出
//  - ネスト型・extension 内型・ルート型の所属を区別可能な形でシンボルを返す
//  - SwiftPM ターゲット名（モジュール名）のベストエフォート解決を内包
//
//  主要機能
//  - 型宣言（Class / Struct / Enum / Protocol / Actor）を訪問しスコープスタックで親子関係を追跡
//  - extension 自身を "Extension" 種別シンボルとして登録（REQ-005 §4.4.1）
//  - Function / Variable / TypeAlias / Macro の宣言抽出
//  - Package.swift を遡って探索しモジュール名を解決（取得失敗時は nil）
//
//  含まれる型
//  - SymbolVisitorV2: スコープスタックを保持する SyntaxVisitor サブクラス
//
//  関連型
//  - SwiftSyntaxAnalyzer.SymbolInfoV2（解析結果のデータ型）
//

import Foundation
import SwiftSyntax

/// スコープ情報付きシンボルを抽出する Visitor（DES-104 §4.5）
///
/// `SymbolVisitor` は継承せず独立実装する（DES-104 §4.5 「`SymbolVisitor` を継承せず独立実装する」方針）。
/// スコープスタック方式により、ネスト型・extension 内型・ルート型を区別する。
///
/// 実装上の重要原則（DES-104 §4.5 / TASK-006 受入基準）:
/// - `visit` で push、`visitPost` で pop の対称性を厳守
/// - 早期 return が起こりうる経路では `defer { scopeStack.removeLast() }` 等は採用しない
///   （DES-104 §4.5 「二重 pop によるスタック崩壊を招くため行わない」方針に従う）
/// - `visit` メソッドは必ず `.visitChildren` を返す（`.skipChildren` を返すと visitPost が呼ばれずスタック崩壊する）
final class SymbolVisitorV2: SyntaxVisitor {
    /// 抽出されたシンボル一覧
    var symbols: [SwiftSyntaxAnalyzer.SymbolInfoV2] = []

    /// SwiftSyntax の位置変換器
    private let converter: SourceLocationConverter

    /// 解析対象ファイルパス（モジュール名解決に使用）
    private let filePath: String

    /// 解決済みモジュール名（最初に 1 度だけ解決し以後再利用、見つからなかった場合も nil をキャッシュ）
    private let resolvedModuleName: String?

    /// スコープスタック
    /// - Element: (name: スコープを構成する型名 / extension 対象型名, isExtension: extension スコープなら true)
    /// - 型宣言で push、`visitPost` で pop。スタック整合性は visit/visitPost の対称性で保証する。
    private var scopeStack: [(name: String, isExtension: Bool)] = []

    init(converter: SourceLocationConverter, filePath: String) {
        self.converter = converter
        self.filePath = filePath
        // モジュール名はファイル単位で固定なので初期化時に 1 度だけ解決
        self.resolvedModuleName = Self.resolveModuleName(from: filePath)
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - 型宣言の visit / visitPost

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        appendSymbol(name: name, kind: "Class", line: node.startLocation(converter: converter).line)
        // 自身を非 extension スコープとして push（子要素から見て親に該当する）
        scopeStack.append((name: name, isExtension: false))
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        // visit 側で必ず push しているため対称に pop する
        popScope()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        appendSymbol(name: name, kind: "Struct", line: node.startLocation(converter: converter).line)
        scopeStack.append((name: name, isExtension: false))
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        popScope()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        appendSymbol(name: name, kind: "Enum", line: node.startLocation(converter: converter).line)
        scopeStack.append((name: name, isExtension: false))
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        popScope()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        appendSymbol(name: name, kind: "Protocol", line: node.startLocation(converter: converter).line)
        scopeStack.append((name: name, isExtension: false))
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        popScope()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        appendSymbol(name: name, kind: "Actor", line: node.startLocation(converter: converter).line)
        scopeStack.append((name: name, isExtension: false))
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        popScope()
    }

    // MARK: - Extension 宣言

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // extension の対象型名（例: extension Foo.Bar { ... } の "Foo.Bar"）
        let extendedType = node.extendedType.trimmedDescription
        // REQ-005 §4.4.1 受入基準: extension 自身も "Extension" 種別のシンボルとして emit する
        appendSymbol(
            name: extendedType,
            kind: "Extension",
            line: node.startLocation(converter: converter).line
        )
        // extension スコープとして push（DES-104 §4.5 決定規則: extension エントリは isExtension=true）
        scopeStack.append((name: extendedType, isExtension: true))
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        popScope()
    }

    // MARK: - その他のシンボル宣言（スコープを作らない）

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        appendSymbol(
            name: node.name.text,
            kind: "TypeAlias",
            line: node.startLocation(converter: converter).line
        )
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        appendSymbol(
            name: node.name.text,
            kind: "Function",
            line: node.startLocation(converter: converter).line
        )
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let line = node.startLocation(converter: converter).line
        // VariableDecl は複数バインディング（let a = 1, b = 2）に対応するためループする
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                appendSymbol(
                    name: identifier.identifier.text,
                    kind: "Variable",
                    line: line
                )
            }
        }
        return .visitChildren
    }

    // Swift 5.9+: Macro 宣言（既存 SymbolVisitor と互換のため抽出）
    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        appendSymbol(
            name: node.name.text,
            kind: "Macro",
            line: node.startLocation(converter: converter).line
        )
        return .visitChildren
    }

    // MARK: - Private Helpers

    /// 現在のスコープスタックから parentScope と extensionTarget を決定し、シンボル登録する
    ///
    /// 決定規則（DES-104 §4.5）:
    /// - `parentScope`: スタックの直近の **非 extension** エントリ名。なければ nil
    /// - `extensionTarget`: スタック内の直近の **extension** エントリ対象型。なければ nil
    private func appendSymbol(name: String, kind: String, line: Int) {
        let parentScope = scopeStack.last(where: { !$0.isExtension })?.name
        let extensionTarget = scopeStack.last(where: { $0.isExtension })?.name

        symbols.append(
            SwiftSyntaxAnalyzer.SymbolInfoV2(
                name: name,
                kind: kind,
                line: line,
                parentScope: parentScope,
                extensionTarget: extensionTarget,
                moduleName: resolvedModuleName
            )
        )
    }

    /// スコープスタックを 1 つ pop する。
    /// スタックが空の状態で呼ばれることは visit/visitPost 対称性が保たれる限り発生しない。
    /// 万一空の場合（バグ）に備え何もしない。
    private func popScope() {
        guard !scopeStack.isEmpty else { return }
        scopeStack.removeLast()
    }

    // MARK: - モジュール名解決ヘルパー（DES-104 §4.5 / TBD-002）

    /// SwiftPM ターゲット名をベストエフォートで解決する
    ///
    /// 方針（DES-104 §2 TBD-002 採用方針）:
    /// 1. `filePath` の親方向に Package.swift を探索（FileManager.fileExists で確認）
    /// 2. 見つかれば内容を読み、`name: "..."` を正規表現抽出（最初に一致したターゲット名）
    /// 3. ファイルパスが `Sources/{target}/` 配下のいずれかに合致すればその target をモジュール名として返す
    /// 4. 上記いずれかが満たせない（Package.swift 不在 / Sources/{target}/ 不一致 / パース失敗）場合は nil
    ///
    /// 精度の制限（DES-104 §4.5 「複数ターゲット構成の精度制限」）:
    /// - 複数ターゲット構成では Package.swift 内で最初に一致した `name: "..."` 値を採用する
    ///   ため、実際の所属ターゲットと異なる名前を返す可能性がある（ベストエフォート）
    /// - throws せず常に Optional<String> を返す（呼び出し側はエラー処理不要）
    static func resolveModuleName(from filePath: String) -> String? {
        // 1. 親ディレクトリを遡って Package.swift を探す
        guard let packageURL = findPackageSwift(startingFrom: filePath) else {
            return nil
        }

        // 2. Package.swift の内容を読み取り
        guard let packageContent = try? String(contentsOf: packageURL, encoding: .utf8) else {
            return nil
        }

        // 3. `name: "..."` を正規表現で抽出（最初にマッチしたものを採用）
        //    Package(name: "Foo") やターゲット定義 .target(name: "Foo", ...) の両方にマッチする
        guard let firstName = extractFirstName(from: packageContent) else {
            return nil
        }

        // 4. ファイルパスが Sources/{target}/ 配下にあるかチェック
        //    Package.swift が置かれているディレクトリからの相対パスで Sources/<target>/ を含むか
        let packageDir = packageURL.deletingLastPathComponent().path
        let sourcesPrefix = packageDir.hasSuffix("/")
            ? "\(packageDir)Sources/"
            : "\(packageDir)/Sources/"

        guard filePath.hasPrefix(sourcesPrefix) else {
            // Sources/ 配下ではない（テストファイル等の Tests/、Plugins/ など）→ 解決不能
            return nil
        }

        // Sources/ 以降の最初のディレクトリ名を target 名として取り出す
        let relativeAfterSources = String(filePath.dropFirst(sourcesPrefix.count))
        guard let firstSlashIndex = relativeAfterSources.firstIndex(of: "/") else {
            // Sources/ 直下にファイルが置かれている形（ターゲット名なし）→ パース失敗扱い
            return nil
        }
        let targetDirName = String(relativeAfterSources[..<firstSlashIndex])

        // ベストエフォート判定: ファイルパス上の target ディレクトリ名と
        // Package.swift から抽出した最初の name が一致するなら採用、それ以外は nil
        // DES-104 §4.5「発見・抽出失敗時はいずれも nil を返す」/ §2 TBD-002 の方針に従い、
        // path: "Sources" 等で targetDirName と target 名が一致しないケースは誤推定を避けるため nil を返す
        // （Package.swift の target/path を本格的にパースするのは TBD-002 の精度範囲を超える）
        return targetDirName == firstName ? firstName : nil
    }

    /// `filePath` の親ディレクトリを遡って `Package.swift` を探す
    /// - Returns: 見つかれば Package.swift の URL、見つからなければ nil
    private static func findPackageSwift(startingFrom filePath: String) -> URL? {
        var currentDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        // ルート（"/"）まで遡る。無限ループ防止のため最大階層数で制限
        let maxDepth = 64
        for _ in 0..<maxDepth {
            let candidate = currentDir.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = currentDir.deletingLastPathComponent()
            // ルートに到達したら終了（"/" の親は "/"）
            if parent.path == currentDir.path {
                return nil
            }
            currentDir = parent
        }
        return nil
    }

    /// Package.swift のテキストから最初の `name: "..."` を正規表現抽出する
    /// - Parameter content: Package.swift の全文
    /// - Returns: 最初に一致した name 値。一致なしまたは正規表現生成失敗時は nil
    private static func extractFirstName(from content: String) -> String? {
        // `name:` の直後に空白を許容し、ダブルクォートで囲まれた識別子を取得する
        // パッケージ名・ターゲット名で広く使われる形式（[A-Za-z_][A-Za-z0-9_-]*）に限定
        let pattern = #"name:\s*"([A-Za-z_][A-Za-z0-9_\-]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              match.numberOfRanges >= 2,
              let nameRange = Range(match.range(at: 1), in: content)
        else {
            return nil
        }
        return String(content[nameRange])
    }
}
