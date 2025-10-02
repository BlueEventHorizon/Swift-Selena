# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

**SwiftCodeAnalyzer**は、SourceKit-LSP統合を通じてSwiftコード解析機能を提供するMCP (Model Context Protocol) サーバーです。Swiftプロジェクトのコードインテリジェンスツールを公開します。

## ビルド・実行コマンド

```bash
# プロジェクトのビルド
swift build

# サーバーの実行
swift run

# Xcodeで開く
open .swiftpm/xcode/package.xcworkspace

# ビルド成果物のクリーンアップ
swift package clean
```

## アーキテクチャ

### コアコンポーネント

1. **SwiftMCPServer.swift** (メインエントリポイント)
   - コード解析用の9つのツールを持つMCPサーバーを構成
   - SourceKitLSPClientとProjectMemoryのライフサイクルを管理
   - 非同期CallToolハンドラを介してツール実行を処理
   - 通信にstdioトランスポートを使用

2. **SourceKitLSPClient.swift** (LSP通信レイヤー)
   - `xcrun`経由で`sourcekit-lsp`サブプロセスを起動・管理
   - stdin/stdoutパイプ上でJSON-RPCプロトコルを実装
   - Swift固有の操作を提供：シンボル検索、定義、参照、ドキュメントシンボル
   - LSP初期化ハンドシェイク (initialize → initialized) を処理
   - **改善済み**: 非同期ストリーミング応答読み取り、堅牢なContent-Lengthパース、Actorベースのスレッドセーフな応答管理

3. **ProjectMemory.swift** (永続ストレージ)
   - `~/.swift-mcp-server/projects/{projectName}/memory.json`にプロジェクトメタデータを保存
   - LSPクエリを減らすためシンボル情報とファイルインデックスをキャッシュ
   - タグとタイムスタンプ付きのメモ機能を提供
   - ファイルの更新日時を追跡して古いキャッシュを無効化

### ツールフロー

全てのツールは以下のパターンに従います：
1. クライアントがstdio経由でMCPツールを呼び出し
2. SwiftMCPServerがCallTool内の適切なハンドラにルーティング
3. ハンドラがパラメータを検証し、LSPClientまたはProjectMemoryを呼び出し
4. 必要に応じてLSPClientがsourcekit-lspにJSON-RPCを送信
5. レスポンスをフォーマットしてCallTool.Resultとして返却

**重要**: `initialize_project`を最初に呼び出す必要があります - これがLSPサブプロセスを起動しProjectMemoryを初期化します。他の全てのツールはこの状態に依存します。

### LSP統合の詳細

- **プロセスライフサイクル**: sourcekit-lspは`initialize_project`で起動、deinitで終了
- **ドキュメント処理**: シンボル/定義をクエリする前に`textDocument/didOpen`でファイルを開く
- **座標系**: LSPは0インデックスの行/列を使用、ツールもLSPに合わせて0インデックスで公開
- **レスポンスパース**: 堅牢なContent-Lengthヘッダーパース（複数メッセージ対応、バッファリング）
- **非同期処理**: `ResponseManager` actorによるスレッドセーフな応答管理、CheckedContinuationでリクエスト/レスポンスをマッチング
- **ストリーミング読み取り**: FileHandleの`readabilityHandler`を使った非同期ストリーミング（100msスリープ不要）

### メモリシステム

ProjectMemoryは3つのインデックスを保持：
- `fileIndex`: ファイルパスをFileInfo（最終更新日、シンボル数）にマッピング
- `symbolCache`: シンボル名をファイル間の位置情報にマッピング
- `notes`: タイムスタンプとタグ付きのユーザー注釈

メモリはJSON encodingでセッション間で永続化されます。変更後は`save()`を呼び出してください。

## ツールカテゴリ

### プロジェクトセットアップ
- `initialize_project`: 最初に呼び出す必要がある

### コードナビゲーション (LSPバック)
- `find_symbol`: ワークスペース全体のシンボル検索
- `get_document_symbols`: ファイル内の全シンボルをリスト
- `get_definition`: 定義へジャンプ
- `find_references`: 全ての使用箇所を検索

### コンテキスト効率的な読み取り
- `read_function_body`: 単一関数の実装を抽出（シンプルなブレースカウント）
- `read_lines`: 特定の行範囲を読み取り

### メモリ/ノート
- `add_note`: 観察内容を永続化
- `search_notes`: 保存されたノートをクエリ
- `get_project_stats`: キャッシュ統計を表示

## 開発メモ

- **Swiftバージョン**: 5.9+、macOS 13+が必要
- **依存関係**: 公式MCP Swift SDK (0.10.2+) を使用
- **LSP可用性**: `xcrun sourcekit-lsp`が利用可能であることを前提（Xcodeに標準搭載）
- **エラーハンドリング**: ツールはMCPError.invalidParamsまたはMCPError.invalidRequestをthrow
- **ロギング**: .infoレベルでswift-logを使用してstdoutに出力
- **サーバーライフタイム**: start後、1000秒のスリープループで無期限に実行

## コードパターン

### 新しいツールの追加方法

1. `ListTools`ハンドラにTool定義を追加（31-203行目付近）
2. `CallTool`のswitch文にcaseを追加（209-389行目付近）
3. `params.arguments`からパラメータを抽出・検証
4. LSPClientまたはProjectMemoryのメソッドを呼び出し
5. レスポンスを.textコンテンツを持つCallTool.Resultとしてフォーマット

### LSPリクエストパターン
```swift
let request = [
    "jsonrpc": "2.0",
    "id": nextId(),
    "method": "lsp/method",
    "params": [/* ... */]
] as [String: Any]
let response = try await sendRequest(request)
```

### シンボル種別マッピング
LSPのkind整数から文字列へのマッピングはSourceKitLSPClient.swift:317-329の`symbolKindName()`を参照（5=Class, 12=Function, など）
