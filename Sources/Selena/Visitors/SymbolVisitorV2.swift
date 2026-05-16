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

    /// Package.swift から抽出した target エントリ（name と任意の path）
    private struct TargetEntry {
        let name: String
        /// `.target(name:..., path: "...")` で明示された path（未指定なら nil → 規約通り Sources/{name}/）
        let path: String?
    }

    /// SwiftPM ターゲット名をベストエフォートで解決する
    ///
    /// 方針（DES-104 §2 TBD-002 採用方針 + path: 属性対応）:
    /// 1. `filePath` の親方向に Package.swift を探索（FileManager.fileExists で確認）
    /// 2. Package.swift から `.target(...)` / `.executableTarget(...)` / `.testTarget(...)` 等の
    ///    ターゲット定義ブロックを括弧深度で取り出し、各ブロックから name と（あれば）path を抽出
    /// 3. 各 target のルートディレクトリを計算:
    ///    - `path: "..."` 指定あり → `{packageDir}/{path}/`
    ///    - 未指定 → 規約通り `{packageDir}/Sources/{name}/`
    /// 4. filePath が最も長い prefix にマッチする target 名を返す（最長一致で曖昧性解消）
    /// 5. マッチしない / target ブロックが取れない場合 → 旧ロジック（Sources/{firstName}/ の照合）にフォールバック
    /// 6. それも失敗 → nil
    ///
    /// 制限:
    /// - Package.swift の Swift コード本格 parse は行わない（正規表現 + 括弧深度の簡易解析）
    /// - 文字列リテラル内の `(` や `)`、コメント内のキーワードで誤動作する可能性は残る
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

        let packageDir = packageURL.deletingLastPathComponent().path

        // 3. ターゲット定義ブロックを抽出し name / path を取り出す
        let targets = parseTargets(from: packageContent)

        // 4. 各 target のルートディレクトリを計算し最長 prefix マッチ
        if !targets.isEmpty {
            var bestMatch: (name: String, rootLen: Int)?
            for target in targets {
                let root = targetRootDirectory(packageDir: packageDir, target: target)
                if filePath.hasPrefix(root) {
                    let len = root.count
                    if bestMatch == nil || len > bestMatch!.rootLen {
                        bestMatch = (target.name, len)
                    }
                }
            }
            if let match = bestMatch {
                return match.name
            }
        }

        // 5. target ブロック解析失敗 or 未マッチ → 旧来の Sources/{firstName}/ パターン照合へフォールバック
        return resolveByLegacySourcesPattern(filePath: filePath, packageDir: packageDir, packageContent: packageContent)
    }

    /// `target` のルートディレクトリ絶対パスを末尾 `/` 付きで返す
    /// - path 指定あり: `{packageDir}/{path}/`（path が絶対パスならそのまま）
    /// - 未指定: `{packageDir}/Sources/{name}/`
    private static func targetRootDirectory(packageDir: String, target: TargetEntry) -> String {
        let dir = packageDir.hasSuffix("/") ? packageDir : packageDir + "/"
        let raw: String
        if let p = target.path {
            raw = p.hasPrefix("/") ? p : dir + p
        } else {
            raw = "\(dir)Sources/\(target.name)"
        }
        return raw.hasSuffix("/") ? raw : raw + "/"
    }

    /// Package.swift の旧来 Sources/{firstName}/ パターン照合（target ブロック解析が空振った場合の保険）
    private static func resolveByLegacySourcesPattern(
        filePath: String,
        packageDir: String,
        packageContent: String
    ) -> String? {
        guard let firstName = extractFirstName(from: packageContent) else { return nil }
        let sourcesPrefix = packageDir.hasSuffix("/")
            ? "\(packageDir)Sources/"
            : "\(packageDir)/Sources/"
        guard filePath.hasPrefix(sourcesPrefix) else { return nil }
        let relativeAfterSources = String(filePath.dropFirst(sourcesPrefix.count))
        guard let firstSlashIndex = relativeAfterSources.firstIndex(of: "/") else { return nil }
        let targetDirName = String(relativeAfterSources[..<firstSlashIndex])
        return targetDirName == firstName ? firstName : nil
    }

    /// Package.swift の文字列から `.target(...)` 系ブロックを走査し name / path を抽出する
    ///
    /// 対応キーワード（SwiftPM の Target 系 DSL）:
    /// `.target(`, `.executableTarget(`, `.testTarget(`, `.plugin(`, `.binaryTarget(`,
    /// `.systemLibrary(`, `.macro(`
    ///
    /// 各ブロックの範囲は **括弧深度** で識別し、ブロック内の **最初の** `name:` と
    /// **最初の** `path:` を採用する（dependencies 内の `.product(name: ...)` 等は
    /// ブロック内の最初の name より後に来る慣習に依存したベストエフォート）。
    private static func parseTargets(from content: String) -> [TargetEntry] {
        let keywords = [
            ".target(",
            ".executableTarget(",
            ".testTarget(",
            ".plugin(",
            ".binaryTarget(",
            ".systemLibrary(",
            ".macro("
        ]

        var entries: [TargetEntry] = []
        var searchStart = content.startIndex

        while searchStart < content.endIndex {
            // 次に出現するキーワードを探す（複数候補のうち最も早いもの）
            var nextKwStart: String.Index?
            var nextKwLen = 0
            for kw in keywords {
                if let r = content.range(of: kw, range: searchStart..<content.endIndex) {
                    if nextKwStart == nil || r.lowerBound < nextKwStart! {
                        nextKwStart = r.lowerBound
                        nextKwLen = kw.count
                    }
                }
            }
            guard let kwStart = nextKwStart else { break }

            // キーワード末尾の `(` の位置（例: ".target(" の最後の文字）
            let openParenIndex = content.index(kwStart, offsetBy: nextKwLen - 1)
            guard let closeIndex = matchingCloseParen(in: content, openAt: openParenIndex) else {
                // 括弧対応が取れない（不正な Package.swift もしくは parse 失敗）→ そのブロックはスキップ
                searchStart = content.index(after: openParenIndex)
                continue
            }

            // `(` の次〜`)` の直前までをブロック本体とする
            let blockStart = content.index(after: openParenIndex)
            let block = String(content[blockStart..<closeIndex])

            if let name = extractFirstName(from: block) {
                let path = extractFirstPath(from: block)
                entries.append(TargetEntry(name: name, path: path))
            }

            // 次の検索開始位置は `)` の直後
            searchStart = content.index(after: closeIndex)
        }

        return entries
    }

    /// `openAt` 位置の `(` に対応する `)` の位置を、括弧深度で見つけて返す
    private static func matchingCloseParen(in content: String, openAt openIndex: String.Index) -> String.Index? {
        guard content[openIndex] == "(" else { return nil }
        var depth = 0
        var i = openIndex
        while i < content.endIndex {
            switch content[i] {
            case "(":
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return i }
            default:
                break
            }
            i = content.index(after: i)
        }
        return nil
    }

    /// 文字列から最初の `path: "..."` を抽出する（target ブロック内利用）
    private static func extractFirstPath(from content: String) -> String? {
        let pattern = #"path:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              match.numberOfRanges >= 2,
              let pathRange = Range(match.range(at: 1), in: content)
        else {
            return nil
        }
        return String(content[pathRange])
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
