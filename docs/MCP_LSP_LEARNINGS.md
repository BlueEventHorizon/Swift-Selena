# MCP・LSP 重要知見集

**作成日**: 2025-10-27
**目的**: MCP（Model Context Protocol）とLSP（Language Server Protocol）の実装で得た重要な知見を記録

---

## MCP (Model Context Protocol)

### StdioTransportの仕様

**クライアント・サーバー関係**:
- **1クライアント = 1サーバープロセス**（必須）
- 複数クライアントで1プロセス共有は**不可能**
- 公式仕様: "Single client connection only"
- 複数クライアント対応にはSSE Transport必要

**プロセスライフサイクル**:
```swift
// 誤った実装
try await server.start(transport: transport)
// ここで即座に終了 → サーバー動作しない

// 正しい実装
try await server.start(transport: transport)
await server.waitUntilCompleted()  // EOF待機（必須）
logger.info("Server stopped")
```

**重要ポイント**:
- `server.start()`: 非ブロッキング、即座にreturn
- `server.waitUntilCompleted()`: EOF受信までブロッキング待機
- 無限ループ（`while true`）は不要、むしろゾンビプロセスの原因

**シャットダウンフロー**:
1. クライアント → stdinを閉じる
2. サーバー → EOF検知、`waitUntilCompleted()`がreturn
3. プロセス正常終了

無限ループがあると、EOF受信してもプロセスが終了しない。

---

### MCP_CLIENT_IDの意味

**誤解**: 1プロセスで複数クライアント処理のため
**正解**: データ分離のため

**仕組み**:
- 各クライアントが独自プロセスを起動（StdioTransportの仕様）
- データは共有ストレージ（`~/.swift-selena/clients/{clientId}/`）
- MCP_CLIENT_IDでキャッシュ・メモリを分離

**ユースケース**:
- Claude DesktopとClaude Codeでキャッシュ分離
- 同じプロジェクトでもクライアント別の設定を保持

---

### 開発版と本番版の分離

**問題**: debugビルドを`swift-selena`として登録 → 本番環境が影響を受ける

**解決**: 別名登録
```bash
# 本番
claude mcp add swift-selena -- /path/to/release/Swift-Selena

# 開発（別名）
claude mcp add swift-selena-debug -- /path/to/debug/Swift-Selena
```

**効果**:
- ツールプレフィックス: `mcp__swift-selena__*` vs `mcp__swift-selena-debug__*`
- 完全分離、本番環境に影響なし
- DebugRunnerの5秒待機が本番に影響しない

---

## LSP (Language Server Protocol)

### SourceKit-LSPのプロジェクト対応状況

**公式サポート**:
- ✅ Swift Package Manager
- ✅ CMakeプロジェクト（`compile_commands.json`）
- ❌ **Xcodeプロジェクト（.xcodeproj/.xcworkspace）未サポート**

**出典**:
- GitHub Issue #730: "SourceKit-LSP doesn't yet support Xcode projects"
- 公式README: Swift PackageとCMakeのみ明記

**回避策**:
- `xcode-build-server`（サードパーティ、Build Server Protocol実装）
- Swift-Selenaでは未対応

---

### XcodeプロジェクトでのLSP動作制限

**テスト結果（ContactB: Xcodeプロジェクト）**:

| LSP API | 動作 | 詳細 |
|---------|------|------|
| textDocument/documentSymbol | ✅ | 型情報付きシンボル一覧取得可能 |
| textDocument/prepareTypeHierarchy | ✅ | 継承関係取得可能 |
| textDocument/references | ❌ | **常に0件**（グローバルインデックス不可） |

**理由**:
- グローバルインデックス（IndexStoreDB）が構築されない
- クロスファイル参照検索に必要なインデックスが利用不可
- 単一ファイル内の解析（documentSymbol/typeHierarchy）は動作

**Swift Packageでは全て動作**:
- textDocument/references: 39件検出（完全動作）
- 全LSP API正常動作

---

### LSPの非同期通知処理

**問題**:
```swift
let data = handle.availableData  // 全バッファ取得
```
→ レスポンス + 非同期通知（publishDiagnostics）が混在

**解決（v0.5.5）**:
```swift
while !remainingText.isEmpty {
    // Content-Lengthで1メッセージずつ切り出し
    // メッセージ種別判定（id有無）
    if jsonPart.contains("\"id\":") {
        return jsonPart  // 応答メッセージ
    } else {
        logger.debug("Skipping async notification...")
        continue  // 非同期通知はスキップ
    }
}
```

**ポイント**:
- Content-Lengthで正確に1メッセージ切り出し
- `"id"`の有無でメッセージ種別判定
- 非同期通知は無視、応答のみ返す

---

### 複数プロジェクト対応

**問題（v0.5.4まで）**:
```swift
private var lspClient: LSPClient?  // 1つだけ
```
→ プロジェクト切り替え時に上書きされる

**解決（v0.5.5）**:
```swift
private var lspClients: [String: LSPClient] = [:]  // プロジェクトパスがキー
private var currentProjectPath: String?
```

**重要**:
- 各プロジェクトのLSPClientを保持
- `initialize_project`でcurrentProjectPath切り替え
- プロジェクト間でLSP状態を保持

---

### initialize_projectでのLSP接続タイミング

**問題（v0.5.4まで）**:
```swift
Task {
    await lspState.tryConnect(projectPath)  // バックグラウンド
}
return Result(...)  // 即座にreturn
```
→ LSP接続完了前にツール実行 → 空結果

**解決（v0.5.5）**:
```swift
let lspAvailable = await lspState.tryConnect(projectPath)  // 同期待機
return Result(...)  // 接続完了後にreturn
```

**効果**:
- LSP接続完了後にツール実行可能
- 空結果を回避

---

## 開発時の教訓

### 1. 公式仕様の完全理解が必須

**失敗例**:
- 「1プロセスで複数クライアント処理できる」と誤解
- ドキュメントを読まずに無限ループ削除

**教訓**:
- 公式仕様・Issueを必ず確認
- 他の実装例を参考にする
- 推測で変更しない

### 2. プラットフォーム制限の事前調査

**失敗例**:
- find_symbol_references実装後、Xcodeプロジェクトで動作しないと判明
- v0.5.2-v0.5.3の実装工数が無駄に

**教訓**:
- 新機能実装前にプラットフォーム制限を調査
- 主要ユースケース（Xcodeプロジェクト）での動作を最優先
- 「接続成功」≠「全機能動作」

### 3. テストは実際のMCPツールとして実行

**ダメな例**:
- ❌ Bashスクリプトで直接ロジック再実装
- ❌ `strings`コマンドでバイナリ確認
- ❌ 「〜件返されるはず」と推測

**正しい例**:
- ✅ 実際にMCPツールとして呼び出す
- ✅ 実際の結果を確認
- ✅ 期待値と比較検証

---

## 参考リンク

- [MCP 公式仕様](https://modelcontextprotocol.io/specification)
- [SourceKit-LSP Issue #730](https://github.com/swiftlang/sourcekit-lsp/issues/730) - Xcodeプロジェクトサポート
- CONVERSATION_HISTORY.md - 詳細な開発履歴

---

**次のバージョン**: v0.6.0 - Code Header DB、意図ベース検索
