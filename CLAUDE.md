# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## 開発時の基本原則

### 1. 仕様を必ず最初に確認する

新しいツール、ライブラリ、記法を使う前に公式ドキュメントを読んでください。

- 思い込みで実装しない
- 「知っている」と思っても確認する
- バージョンの仕様変更を把握する

### 2. 小さく試してから大きく展開する

一度に大量生産せず、1つを完成させてから次へ進んでください。

- 1つのサンプルで動作確認
- 問題なければ他に展開
- エラーが出てから修正では遅い

### 3. 品質を最優先する

スピードより正確性を重視してください。

- 推測より確認
- 複雑な正規表現を使って一括置換や、一括変更しない
  - 間違った場合に手戻りが膨大です
  - 単純置換などはOK
- 手抜きしない（全力で作業に向き合ってください）

---

## プロジェクト概要

**Swift Selena**は、ファイルシステム検索とSwiftSyntax静的解析を使用してSwiftコード解析機能を提供するMCP (Model Context Protocol) サーバーです。ビルドエラーがある実装中のコードでも動作する実用的なツールセットを提供します。

## ビルド・実行コマンド

```bash
# プロジェクトのビルド（開発用）
swift build

# 本番用リリースビルド
swift build -c release -Xswiftc -Osize

# セットアップスクリプトに実行権限を付与
chmod +x register-mcp-to-claude-desktop.sh
chmod +x register-selena-to-claude-code.sh

# Claude Desktopに登録（自動）
./register-mcp-to-claude-desktop.sh

# Claude Codeに登録（自動）
./register-selena-to-claude-code.sh

# サーバーの実行（開発用）
swift run

# Xcodeで開く
open .swiftpm/xcode/package.xcworkspace

# ビルド成果物のクリーンアップ
swift package clean
```

## アーキテクチャ

### コアコンポーネント

1. **SwiftMCPServer.swift** (メインエントリポイント)
   - コード解析用のMCPサーバーを構成（17-18ツール）
   - ProjectMemoryとLSPStateのライフサイクルを管理
   - 非同期CallToolハンドラを介してツール実行を処理
   - 通信にstdioトランスポートを使用
   - 動的ツールリスト生成（LSP利用可能時にLSPツール追加）
   - **FileSearcher**: ファイルシステムベースの検索（ワイルドカード、grep的検索）
   - **SwiftSyntaxAnalyzer**: ビルド不要のAST解析によるシンボル抽出
   - **LSPState/LSPClient**: ビルド可能時のLSP統合（v0.5.1+）

2. **ProjectMemory.swift** (永続ストレージ)
   - `~/.swift-selena/clients/{clientId}/projects/{projectName}-{hash}/memory.json`にプロジェクトメタデータを保存
   - クライアント識別子（環境変数`MCP_CLIENT_ID`）で複数クライアント対応（デフォルト: "default"）
   - プロジェクトパスのSHA256ハッシュ（8文字）で同一プロジェクトを識別
   - 再起動後も同じプロジェクトのデータを永続化、異なるプロジェクトは自動的に分離
   - シンボル情報とファイルインデックスをキャッシュ
   - タグとタイムスタンプ付きのメモ機能を提供
   - ファイルの更新日時を追跡して古いキャッシュを無効化

### ツールフロー

全てのツールは以下のパターンに従います：
1. クライアントがstdio経由でMCPツールを呼び出し
2. SwiftMCPServerがCallTool内の適切なハンドラにルーティング
3. ハンドラがパラメータを検証し、FileSearcher/SwiftSyntaxAnalyzer/ProjectMemoryを呼び出し
4. レスポンスをフォーマットしてCallTool.Resultとして返却

**重要**: `initialize_project`を最初に呼び出す必要があります - これがProjectMemoryを初期化します。メモリ機能を使う全てのツールはこの状態に依存します。

### 検索・解析の実装詳細

**FileSearcher** (ファイルシステムベース):
- **ファイル検索**: ワイルドカードパターン（`*Controller.swift`など）をNSRegularExpressionに変換
- **コード検索**: 正規表現でファイル内容をgrep的に検索
- **利点**: ビルド不要、実装中のコードでも動作

**SwiftSyntaxAnalyzer** (静的AST解析):
- **シンボル抽出**: SwiftParserでソースをパース、SyntaxVisitorでASTを走査
- **対応シンボル**: Class, Struct, Enum, Protocol, Function, Variable
- **位置情報**: SourceLocationConverterで行番号を取得
- **利点**: ビルドエラーがあっても構文が正しければ動作

**LSPState/LSPClient** (型情報ベース解析、v0.5.1+):
- **LSP接続管理**: SourceKit-LSPプロセスの起動・初期化・切断
- **スレッドセーフ**: Actorで並行アクセスを安全に管理
- **グレースフルデグレード**: ビルド不可の場合はSwiftSyntaxのみで動作
- **利点**: 型情報を使った正確な参照検索、ビルド可能なプロジェクトで高度な機能を提供

### メモリシステム

ProjectMemoryは3つのインデックスを保持：
- `fileIndex`: ファイルパスをFileInfo（最終更新日、シンボル数）にマッピング
- `symbolCache`: シンボル名をファイル間の位置情報にマッピング
- `notes`: タイムスタンプとタグ付きのユーザー注釈

メモリはJSON encodingでセッション間で永続化されます。変更後は`save()`を呼び出してください。

## ツールカテゴリ

### プロジェクトセットアップ
- `initialize_project`: 最初に呼び出す必要がある（ProjectMemory初期化）

### ファイルシステム検索
- `find_files`: ワイルドカードパターンでファイル検索（例: `*Controller.swift`）
- `search_code`: 正規表現でコード内容を検索（grep的）

### SwiftSyntax静的解析
- `list_symbols`: ファイル内の全シンボル抽出（Class, Struct, Function等）
- `find_symbol_definition`: プロジェクト全体でシンボル定義を検索
- `list_property_wrappers`: SwiftUI Property Wrapper解析（@State, @Binding, @ObservedObject等）
- `list_protocol_conformances`: Protocol準拠と継承関係の解析（UITableViewDelegate, ObservableObject等）
- `list_extensions`: Extension解析（拡張対象の型、メンバー一覧）
- `analyze_imports`: プロジェクト全体のImport依存関係を解析（キャッシュ利用）
- `get_type_hierarchy`: 型の継承階層を取得（スーパークラス、サブクラス、Protocol準拠型、キャッシュ利用）
- `find_test_cases`: XCTestケースとテストメソッドを検出
- `find_type_usages`: 型の使用箇所を検出（変数宣言、関数パラメータ、戻り値型）

### コンテキスト効率的な読み取り
- `read_symbol`: シンボル単位で読み取り（関数、クラス、構造体等）

### LSP統合機能（v0.5.2+、ビルド可能時のみ）
- `find_symbol_references`: シンボル参照検索（型情報ベース、LSP使用）
  - ファイルパス + 行 + 列で位置指定
  - textDocument/referencesリクエスト使用
  - ビルド不可の場合は利用不可（代替: find_type_usages, search_code）

### メモリ/ノート
- `add_note`: 観察内容を永続化
- `search_notes`: 保存されたノートをクエリ
- `get_project_stats`: キャッシュ統計を表示

## 開発メモ

- **Swiftバージョン**: 5.9+、macOS 13+が必要
- **依存関係**:
  - MCP Swift SDK (0.10.2 exact)
  - SwiftSyntax (602.0.0 exact) - SwiftParser含む
- **ビルド不要**: SourceKit-LSPに依存しないため、実装中のコードでも動作
- **LSP統合**: ビルド可能時はSourceKit-LSPで高度な機能提供（v0.5.1+）
- **エラーハンドリング**: ツールはMCPError.invalidParamsまたはMCPError.invalidRequestをthrow
- **ロギング**: FileLogHandlerで~/.swift-selena/logs/server.logに出力（v0.5.3+）
  - 監視: `tail -f ~/.swift-selena/logs/server.log`
  - デバッグレベル出力、LSPレスポンス詳細表示
- **デバッグ**: DebugRunner（#if DEBUG、Xcodeデバッガ対応、v0.5.3+）
- **サーバーライフタイム**: start後、1000秒のスリープループで無期限に実行

## 複数MCPクライアント対応

環境変数`MCP_CLIENT_ID`を設定することで、Claude CodeとClaude Desktopで同時に使用可能です。

### Claude Desktop設定例 (`claude_desktop_config.json`)
```json
{
  "mcpServers": {
    "swift-selena": {
      "command": "/path/to/.build/debug/SwiftMCPServer",
      "env": {
        "MCP_CLIENT_ID": "claude-desktop"
      }
    }
  }
}
```

### Claude Code設定例 (`mcp_config.json`)
```json
{
  "mcpServers": {
    "swift-selena": {
      "command": "/path/to/.build/debug/SwiftMCPServer",
      "env": {
        "MCP_CLIENT_ID": "claude-code"
      }
    }
  }
}
```

設定しない場合は`default`が使用されます。各クライアントのデータは`~/.swift-selena/clients/{clientId}/`に分離されます。

**重要**: プロジェクトパスのハッシュにより、同じプロジェクトは同じデータを共有し、異なるプロジェクトは自動的に分離されます。複数のClaude Codeウィンドウで異なるプロジェクトを開いても問題ありません。

## コードパターン

### 新しいツールの追加方法

1. `ListTools`ハンドラにTool定義を追加
2. `CallTool`のswitch文にcaseを追加
3. `params.arguments`からパラメータを抽出・検証
4. FileSearcher/SwiftSyntaxAnalyzer/ProjectMemoryのメソッドを呼び出し
5. レスポンスを.textコンテンツを持つCallTool.ResultとしてフォーマットExit

### ファイル検索パターン
```swift
// ワイルドカード検索
let files = try FileSearcher.findFiles(in: projectPath, pattern: "*.swift")

// コード検索
let matches = try FileSearcher.searchCode(
    in: projectPath,
    pattern: "func.*\\(",  // 正規表現
    filePattern: "*.swift"  // オプション
)
```

### SwiftSyntax解析パターン
```swift
// シンボル抽出
let symbols = try SwiftSyntaxAnalyzer.listSymbols(filePath: "/path/to/file.swift")
// 結果: [SymbolInfo(name: "MyClass", kind: "Class", line: 10), ...]

// Property Wrapper解析
let wrappers = try SwiftSyntaxAnalyzer.listPropertyWrappers(filePath: "/path/to/view.swift")
// 結果: [PropertyWrapperInfo(propertyName: "counter", wrapperType: "State", typeName: "Int", line: 4), ...]

// Protocol Conformance解析
let conformances = try SwiftSyntaxAnalyzer.listTypeConformances(filePath: "/path/to/file.swift")
// 結果: [TypeConformanceInfo(typeName: "ViewController", typeKind: "Class",
//        protocols: ["UITableViewDelegate", "UITableViewDataSource"],
//        superclass: "UIViewController", line: 5), ...]
```
