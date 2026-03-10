# MCP開発ベストプラクティス

**目的**: MCPサーバー開発で得た重要な知見を記録（汎用的な内容）

---

## 1. サーバーライフサイクル

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

## 2. 複数クライアント対応

### MCP_CLIENT_IDの意味

**誤解**: 1プロセスで複数クライアント処理のため
**正解**: データ分離のため

**仕組み**:
- 各クライアントが独自プロセスを起動（StdioTransportの仕様）
- データは共有ストレージ（例: `~/.your-app/clients/{clientId}/`）
- MCP_CLIENT_IDでキャッシュ・メモリを分離

**ユースケース**:
- Claude DesktopとClaude Codeでキャッシュ分離
- 同じプロジェクトでもクライアント別の設定を保持

---

## 3. 開発環境の分離

### 開発版と本番版の分離

**問題**: debugビルドを本番名で登録 → 本番環境が影響を受ける

**解決**: 別名登録
```bash
# 本番
claude mcp add your-server -- /path/to/release/YourServer

# 開発（別名）
claude mcp add your-server-debug -- /path/to/debug/YourServer
```

**効果**:
- ツールプレフィックス: `mcp__your-server__*` vs `mcp__your-server-debug__*`
- 完全分離、本番環境に影響なし
- デバッグ機能が本番に影響しない

---

## 4. ツール設計

### ツール命名規則

- スネークケース使用: `find_files`, `list_symbols`
- 動詞で始める: `get_`, `find_`, `list_`, `search_`, `analyze_`
- 名詞は単数/複数を適切に: `find_file` vs `find_files`

### パラメータ設計

```swift
Tool(
    name: "find_files",
    description: "Find files matching a pattern",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "pattern": .object([
                "type": .string("string"),
                "description": .string("Glob pattern (e.g., '*.swift')")
            ])
        ]),
        "required": .array([.string("pattern")])
    ])
)
```

**ポイント**:
- 必須パラメータは`required`に明記
- 説明には具体例を含める
- オプションパラメータはデフォルト値をコードで処理

### エラーメッセージの書き方

```swift
// 悪い例
throw MCPError.invalidParams("error")

// 良い例
throw MCPError.invalidParams("Missing required parameter: project_path")
throw MCPError.invalidRequest("Project not initialized. Call initialize_project first.")
```

---

## 5. デバッグ方法

### ログ設計

```swift
// ファイルログの使用（stdoutはMCP通信用）
let logFilePath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".your-app/logs/server.log")
    .path

LoggingSystem.bootstrap { label in
    if let handler = try? FileLogHandler(logFilePath: logFilePath) {
        return handler
    } else {
        return StreamLogHandler.standardError(label: label)
    }
}
```

**重要**:
- stdoutはMCP通信専用、ログはstderrまたはファイルへ
- ログファイルの場所を起動時に表示
- `tail -f ~/.your-app/logs/server.log` で監視可能に

### MCP Inspectorの使い方

```bash
# MCPインスペクタで接続
npx @modelcontextprotocol/inspector swift run
```

---

## 6. よくある失敗パターン

### パターン1: 無限ループの使用

```swift
// 誤り
while true {
    try await Task.sleep(nanoseconds: 1_000_000_000_000)
}

// 正解
await server.waitUntilCompleted()
```

**結果**: ゾンビプロセス大量発生

### パターン2: 非同期処理の誤用

```swift
// 誤り
Task {
    await initialize()  // バックグラウンド
}
return Result(...)  // 初期化完了前にreturn

// 正解
await initialize()  // 同期待機
return Result(...)  // 初期化完了後にreturn
```

**結果**: 空の結果が返る

### パターン3: パラメータ検証の漏れ

```swift
// 誤り
let path = String(describing: args["path"])  // nilでもクラッシュしない

// 正解
guard let args = params.arguments,
      let pathValue = args["path"] else {
    throw MCPError.invalidParams("Missing required parameter: path")
}
```

**結果**: 不明なエラー、デバッグ困難

---

## 7. テスト方法

### 正しいテストの実施

**ダメな例**:
- Bashスクリプトで直接ロジック再実装
- `strings`コマンドでバイナリ確認
- 「〜件返されるはず」と推測

**正しい例**:
- 実際にMCPツールとして呼び出す
- 実際の結果を確認
- 期待値と比較検証

### DEBUG版でのテスト手順

1. DEBUGビルド: `swift build`
2. 別名で登録: `your-server-debug`
3. Claude Code再起動
4. 実際にツールを呼び出してテスト
5. ログ確認: `tail -f ~/.your-app/logs/server.log`

---

## 8. 公式仕様の確認

### 必ず確認すべきリソース

- [MCP 公式仕様](https://modelcontextprotocol.io/specification)
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
- [JSON-RPC 2.0 仕様](https://www.jsonrpc.org/specification)

### 実装前の確認事項

1. 公式ドキュメントで仕様確認
2. GitHub Issuesで既知の制限を確認
3. 他の実装例を参考にする
4. 推測で実装しない

---

**Document Version**: 1.0
**Created**: 2025-12-26
**Source**: Swift-Selena開発での実践的知見
