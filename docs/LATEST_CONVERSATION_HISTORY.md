# 最新開発履歴サマリー（v0.5.5）

**作成日**: 2025-10-27
**対象**: 次のClaude Codeセッション用
**Document Version**: 1.9

---

## v0.5.5 実装内容

### 新機能
**search_files_without_pattern** - grep -L相当、「ないものを探す」検索
- Code Header未作成ファイルの検出
- Import未記述ファイルの発見
- ContactBで3ファイル検出成功（ViewState.swift, ContactSortType.swift, MKLocalSearch+Async.swift）
- 統計情報: Files checked: 263, Files without pattern: 3 (1.1%)

### 修正したバグ（6件）
1. **正規表現マルチラインモード** - `.anchorsMatchLines`追加、`^import`が各行にマッチ
2. **ゾンビプロセス** - `server.waitUntilCompleted()`でEOF正常終了、無限ループ削除
3. **本番環境汚染** - `swift-selena-debug`別名登録で開発版と本番版を完全分離
4. **LSP非同期通知混入** - Content-Length正確処理、publishDiagnosticsスキップ
5. **LSPState単一プロジェクト** - Dictionary管理で複数プロジェクト対応
6. **initialize_projectバックグラウンド** - 同期待機、LSP接続完了後にreturn

### find_symbol_references削除

**調査結果**:
- Swift Package（Swift-Selena）: 39件検出 ✅
- Xcodeプロジェクト（ContactB）: **常に0件** ❌

**原因**: SourceKit-LSP公式が「Xcodeプロジェクト未サポート」（Issue #730）
- グローバルインデックス（IndexStoreDB）構築不可
- クロスファイル参照検索不可
- documentSymbol/typeHierarchyは動作（単一ファイル解析）

**決断**: 削除（約270行）
- 理由: 動作環境が限定的、代替手段あり（find_type_usages）
- 結果: ツール数 19 → **18**、全プロジェクトタイプで動作

---

## 重要な知見（必読）

### MCP仕様
**プロセスライフサイクル**:
```swift
try await server.start(transport: transport)
await server.waitUntilCompleted()  // EOF待機（必須）
```
- `server.start()`: 非ブロッキング、即座にreturn
- 無限ループは不要、むしろゾンビプロセスの原因

**StdioTransport**: 1クライアント = 1サーバープロセス（必須）

### LSP制限
- **Xcodeプロジェクト**: 参照検索不可、documentSymbol/typeHierarchyは動作
- **Swift Package**: 全機能動作
- **複数プロジェクト**: LSPStateでDictionary管理必須

---

## スクリプトの使い分け（重要）

```bash
# 本番用: 他のプロジェクト（CCMonitor等）に登録（引数必須）
./register-selena-to-claude-code.sh /path/to/target/project

# 開発用: Swift-Selenaプロジェクト自体に登録（引数なし）
./register-selena-to-claude-code-debug.sh
```

**誤解注意**:
- ❌ 両方とも引数なし → 誤り（release版は引数必須）
- ✅ release版: 引数必須、debug版: 引数なし

---

## DEBUGビルドテスト方法

```bash
# 1. クリーンビルドと登録
./register-selena-to-claude-code-debug.sh

# 2. Swift-Selenaプロジェクトで再起動

# 3. MCPツールとしてテスト（重要）
mcp__swift-selena-debug__initialize_project(project_path: "/path/to/ContactB")
mcp__swift-selena-debug__search_files_without_pattern(pattern: "^import")
```

**テストの原則**:
- ❌ Bashスクリプトで直接ロジック再実装
- ❌ stringsコマンドでバイナリ確認
- ✅ 実際にMCPツールとして呼び出す
- ✅ 実際の結果を確認・検証

---

## 現在の構成

- **ツール数**: 18
- **バージョン**: 0.5.5
- **LSP機能**: list_symbols, get_type_hierarchy（フォールバックあり）
- **SwiftSyntax機能**: 16ツール

---

**参考資料**: `docs/MCP_LSP_LEARNINGS.md` - MCP・LSP詳細知見

