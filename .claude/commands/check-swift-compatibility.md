# Swift互換性チェック

SwiftSyntax関連の作業前に、Swiftバージョンと対応状況を確認します。

## 実行手順

### 1. 現在のSwiftバージョン確認

```bash
swift --version
```

### 2. SwiftSyntaxバージョン確認

Package.swiftから使用中のSwiftSyntaxバージョンを確認:
```bash
grep "swift-syntax" Package.swift
```

### 3. SymbolVisitorの対応状況確認

現在対応しているDeclSyntax一覧:
```bash
grep -o "[A-Z][a-zA-Z]*DeclSyntax" Sources/Selena/Visitors/SymbolVisitor.swift | sort -u
```

### 4. SwiftSyntaxで利用可能なDeclSyntax確認

```bash
grep -rh "public struct [A-Z][a-zA-Z]*DeclSyntax:" .build/checkouts/swift-syntax/Sources/SwiftSyntax/ 2>/dev/null | sed 's/.*struct \([A-Za-z]*DeclSyntax\).*/\1/' | grep -v "^Raw" | sort -u
```

### 5. 未対応のDeclSyntax特定

対応済みと利用可能を比較し、不足があれば報告してください。

## チェックリスト

- [ ] Swiftバージョンを確認した
- [ ] SwiftSyntaxバージョンを確認した
- [ ] 現在の対応DeclSyntaxを確認した
- [ ] 利用可能なDeclSyntaxを確認した
- [ ] 不足しているDeclSyntaxを特定した

## バージョン別の重要な構文

| Swiftバージョン | 追加された構文 | 対応DeclSyntax |
|----------------|---------------|----------------|
| Swift 5.5 | actor, async/await | ActorDeclSyntax |
| Swift 5.9 | Macros | MacroDeclSyntax |
| Swift 6.0 | Sendable強制 | - |

## 不足があった場合

SymbolVisitor.swiftに対応ハンドラを追加:

```swift
override func visit(_ node: XXXDeclSyntax) -> SyntaxVisitorContinueKind {
    let location = node.startLocation(converter: converter)
    symbols.append(SwiftSyntaxAnalyzer.SymbolInfo(
        name: node.name.text,  // nameプロパティがあるか確認
        kind: "XXX",
        line: location.line
    ))
    return .visitChildren
}
```

追加後は `make build` でキャッシュクリア＆ビルド。
