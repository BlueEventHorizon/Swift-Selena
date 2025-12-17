# 対話履歴

このファイルは、プロジェクトにおける重要な設計判断や検討内容の履歴を記録します。

## 重要な教訓（サマリー）

### Swiftバージョン対応 [★★★★★]

- **SwiftSyntax DeclSyntax追加漏れ**
  - 対象: `Sources/Visitors/SymbolVisitor.swift`
  - 理由: Swiftのバージョンアップで新しい構文（actor, macro等）が追加される
  - 正解: 作業前に`swift --version`確認、対応DeclSyntaxを確認

| Swiftバージョン | 追加構文 | 対応DeclSyntax |
|----------------|---------|---------------|
| Swift 5.5 | actor | ActorDeclSyntax |
| Swift 5.9 | macro | MacroDeclSyntax |

### キャッシュ無効化 [★★★★★]

- **解析ロジック変更後のキャッシュ問題**
  - 対象: `~/.swift-selena/clients/*/projects/*/memory.json`
  - 理由: SymbolVisitor等を修正しても古いキャッシュが使われる
  - 正解: `make build`でキャッシュ自動クリア（Makefileで対応済み）

### MCPサーバー実装 [★★★★★]

- **server.start()は非ブロッキング**
  - 対象: `Sources/SwiftMCPServer.swift`
  - 理由: 無限ループではなく`waitUntilCompleted()`を使う
  - 正解: `try await server.start(); await server.waitUntilCompleted()`

- **開発版と本番版の分離**
  - 対象: `.claude/mcp_config.json`
  - 理由: 本番環境に影響を与えない
  - 正解: DEBUG版は`swift-selena-debug`として別名登録

### LSPプロトコル [★★★★★]

- **LSP初期化シーケンスの完全実装**
  - 対象: `Sources/LSP/LSPClient.swift`
  - 理由: initialized通知がないと2リクエスト後に終了、didOpenがないと参照検索失敗
  - 正解: initialize → レスポンス読み捨て → initialized通知 → didOpen通知 → リクエスト

- **非同期通知（publishDiagnostics）の混入問題**
  - 対象: `Sources/LSP/LSPClient.swift`
  - 理由: Content-Lengthで1レスポンスずつ切り出さないとバッファが混乱
  - 正解: ResponseBuffer実装でContent-Length単位で処理

### プラットフォーム制限 [★★★★☆]

- **XcodeプロジェクトでのLSP参照検索不可**
  - 対象: SourceKit-LSP
  - 理由: Issue #730 - グローバルインデックス未構築
  - 正解: find_symbol_referencesは削除、find_type_usages（SwiftSyntax）で代替

### 後方互換性 [★★★★☆]

- **memory.jsonへのフィールド追加**
  - 対象: `Sources/ProjectMemory.swift`
  - 理由: 新フィールドがあると既存ファイルがデシリアライズ失敗
  - 正解: 新規フィールドは必ずオプショナル、またはマイグレーション実装

### テスト方法 [★★★★☆]

- **MCPツールとして実際に呼び出す**
  - 理由: Bashスクリプトでロジック再実装してもテストにならない
  - 正解: `mcp__swift-selena-debug__execute_tool`で実際に呼び出す

---

## 詳細履歴

### 2025-12-17: Swift Testing対応 [★★★★☆]

#### 問題

`find_test_cases`がXCTestのみ対応で、Swift Testing（`@Test`アトリビュート）を検出できない。

CCMonitorの状況:
- XCTest: 2クラス、3メソッド
- Swift Testing: 22テストファイル（検出されず）

#### 結論

SwiftTestingVisitorを新規作成し、XCTestとSwift Testing両方を検出可能に。

#### 変更内容

- **Sources/Visitors/SwiftTestingVisitor.swift**: 新規作成
  - `@Test`/`@Suite`アトリビュート検出
  - struct/class/enum対応
  - ディスプレイ名抽出（`@Test("説明")`）

- **Sources/SwiftSyntaxAnalyzer.swift**:
  - `SwiftTestInfo`構造体追加
  - `findSwiftTests()`メソッド追加

- **Sources/Tools/Analysis/FindTestCasesTool.swift**:
  - XCTestとSwift Testing両方を検出・表示

#### テスト結果（CCMonitor）

| フレームワーク | 修正前 | 修正後 |
|--------------|--------|--------|
| XCTest | 2クラス | 2クラス |
| Swift Testing | 0 | 29スイート、187メソッド |

---

### 2025-12-15: ActorDeclSyntax対応 [★★★★★]

#### 問題

`find_symbol_definition`でStreamManager（actor）が見つからない。

#### ユーザー指摘（原文）

> 「現在のSwiftバージョンを知っていますか？」
> 「常にあなたはSwiftのバージョンを気にかけるべきです」

#### 結論

SymbolVisitorに`ActorDeclSyntax`、`MacroDeclSyntax`、`TypeAliasDeclSyntax`を追加。
Makefileにキャッシュ自動クリアを追加。

#### 変更内容

- **Sources/Visitors/SymbolVisitor.swift**:
  - `ActorDeclSyntax`ハンドラ追加（Swift 5.5+）
  - `MacroDeclSyntax`ハンドラ追加（Swift 5.9+）
  - `TypeAliasDeclSyntax`ハンドラ追加

- **Makefile内`build`/`build-release`ターゲット**:
  - キャッシュ自動クリア追加

- **CLAUDE.md内「Swiftバージョンの確認」セクション**:
  - SwiftSyntax作業時のバージョン確認ルール追加

---

### 2025-12-15: メタツールパターン導入 [★★★★☆]

#### 問題

12ツールが全て表示され、トークン使用量が多い。

#### 結論

メタツールパターンで4ツールに集約（list_available_tools, get_tool_schema, execute_tool, initialize_project）。
トークン使用量約63%削減。

#### 変更内容

- **Sources/Tools/Meta/**: MetaToolRegistry, ExecuteToolTool等を新規作成
- **Sources/SwiftMCPServer.swift**: メタツール経由でルーティング

---

### 2025-10-27: ゾンビプロセス問題修正 [★★★★★]

#### 問題

Swift-Selenaプロセスが21個も残留。クライアント切断後もプロセスが終了しない。

#### ユーザー指摘（原文）

> 「プロセスがゾンビになっている」

#### 結論

`server.start()`は非ブロッキング。無限ループではなく`waitUntilCompleted()`でEOF待機。

#### 変更内容

- **Sources/SwiftMCPServer.swift**:
  ```swift
  // 誤り
  while true { try await Task.sleep(...) }

  // 正解
  try await server.start(transport: transport)
  await server.waitUntilCompleted()
  ```

---

### 2025-10-27: find_symbol_references削除 [★★★★☆]

#### 問題

XcodeプロジェクトでLSP参照検索が常に0件。

#### 結論

SourceKit-LSP公式Issue #730: Xcodeプロジェクト未サポート。
Swift Packageでのみ動作する機能は削除。代替: `find_type_usages`（SwiftSyntax版）。

#### 変更内容

- **FindSymbolReferencesTool.swift**: 削除（110行）
- **LSPClient.findReferences()**: 削除（92行）
- ツール数: 19 → 18

---

## アーカイブ

詳細な履歴は `archive/` ディレクトリを参照:
- `CONVERSATION_HISTORY_20251217.md` - v0.1.0〜v0.6.2の全履歴（2699行）
