# Swift-Selena Design Document

## プロジェクト概要

**Swift-Selena**は、Swiftプロジェクトのコード解析を提供するMCP (Model Context Protocol) サーバーです。SourceKit-LSPに依存せず、ビルド不要でローカル完結型のコード理解機能を実現します。

### 名前の由来

- **Swift**: Swift言語専用
- **Selena**: Pythonベースの汎用MCPサーバー「Serena」へのオマージュ

## 背景と動機

### 問題意識

1. **SourceKit-LSPの制約**
   - ビルド可能なプロジェクトが前提
   - 実装中のコード（ビルドエラーがある状態）では機能しない
   - 複雑なプロジェクト設定が必要
2. **既存ツールの限界**
   - Serena: 汎用的だがSwift特有の解析は浅い
   - Xcode: IDEに依存、CLI/MCP統合が困難
   - SourceKitten: SourceKit-LSPのラッパー、同じ制約
3. **実開発での課題**
   - コード実装中（ビルドできない状態）でも解析したい
   - 軽量で高速な解析が必要
   - プライバシー：外部サーバーに接続したくない

### 解決アプローチ

**SwiftSyntaxベースの静的解析**により：

- ✅ ビルド不要
- ✅ 完全ローカル
- ✅ 高速動作
- ✅ 実装中のコードも解析可能

## アーキテクチャ

### コアコンポーネント

```
┌─────────────────────────────────────┐
│   Claude Desktop / Claude Code      │
│          (MCP Client)               │
└──────────────┬──────────────────────┘
               │ MCP Protocol (stdio)
┌──────────────▼──────────────────────┐
│      Swift-Selena MCP Server        │
│  ┌─────────────────────────────┐   │
│  │  Tool Handlers (22 tools)   │   │
│  │  - initialize_project       │   │
│  │  - find_files               │   │
│  │  - search_code              │   │
│  │  - list_symbols             │   │
│  │  - find_symbol_definition   │   │
│  │  - list_property_wrappers   │   │
│  │  - list_protocol_conformances│  │
│  │  - list_extensions          │   │
│  │  - analyze_imports          │   │
│  │  - get_type_hierarchy       │   │
│  │  - find_test_cases          │   │
│  │  - find_type_usages         │   │
│  │  - read_function_body       │   │
│  │  - read_lines               │   │
│  │  - add_note / search_notes  │   │
│  │  - get_project_stats        │   │
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │  SwiftSyntax Parser         │   │
│  │  - AST解析                  │   │
│  │  - シンボル抽出             │   │
│  │  - 構造解析                 │   │
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │  Project Memory             │   │
│  │  - 永続化ストレージ         │   │
│  │  - ノート管理               │   │
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │  Cache System (v0.4.0+)     │   │
│  │  - CacheManager             │   │
│  │  - FileCacheEntry           │   │
│  │  - CacheGarbageCollector    │   │
│  │  - ファイル単位キャッシュ   │   │
│  │  - 自動GC                   │   │
│  └─────────────────────────────┘   │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│   File System (Swift Project)       │
└─────────────────────────────────────┘
```

### 技術スタック

- **言語**: Swift 5.9+
- **MCP SDK**: swift-sdk 0.10.2
- **構文解析**: SwiftSyntax 602.0.0
- **ストレージ**: JSON (FileManager)
- **通信**: Stdio Transport
- **暗号化**: CryptoKit (プロジェクトパスハッシュ)

## 設計原則

### 1. ビルド非依存性

**原則**: プロジェクトがビルド可能かどうかに関わらず動作する

**実装方針**:

- SwiftSyntaxによる構文木解析のみを使用
- コンパイラ情報（型チェック結果）に依存しない
- ファイル単位での独立した解析

### 2. ローカル完結性

**原則**: 外部サーバーへの接続を一切行わない

**理由**:

- プライバシー保護
- オフライン動作
- 低レイテンシ

**禁止事項**:

- クラウドLLMへのAPI呼び出し
- 外部コード解析サービス
- テレメトリ送信

### 3. 軽量性

**原則**: メモリと計算リソースを最小限に抑える

**実装方針**:

- ファイル単位の解析（プロジェクト全体を一度にロードしない）
- オンデマンド解析
- 結果のキャッシュ

### 4. 拡張性

**原則**: 新機能の追加が容易な設計

**アーキテクチャ**:

- ツールハンドラのモジュラー構造
- SwiftSyntaxのVisitorパターン活用
- プラグイン可能な解析機能

## 機能設計

### Tier 1: 基本機能（実装完了 - v0.5.0）

#### ファイルシステム操作

- `initialize_project`: プロジェクトの初期化
- `find_files`: ファイル名パターン検索
- `search_code`: コード内容検索（grep）

#### シンボル解析

- `list_symbols`: ファイル内のシンボル一覧
- `find_symbol_definition`: シンボル定義の検索

#### SwiftUI特化

- `list_property_wrappers`: @State, @Binding等の検出
- `list_protocol_conformances`: プロトコル適合の検出
- `list_extensions`: Extension宣言の一覧

#### 依存関係・階層解析

- `analyze_imports`: Import依存関係解析（モジュール使用統計、キャッシュ利用）
- `get_type_hierarchy`: 型の継承階層取得（スーパークラス、サブクラス、Protocol準拠型、キャッシュ利用）
- `find_test_cases`: XCTestケースとテストメソッド検出
- `find_type_usages`: 型の使用箇所を検出（変数宣言、関数パラメータ、戻り値型）

#### ユーティリティ

- `read_function_body`: 関数実装の抽出
- `read_lines`: 行範囲指定読み取り
- `read_symbol`: シンボル単位読み取り（v0.5.0）
- `read_file`: 汎用ファイル読み取り（v0.5.0）
- `list_directory`: ディレクトリ一覧（v0.5.0）
- `add_note` / `search_notes`: プロジェクトメモ
- `get_project_stats`: 統計情報

#### メタ機能（v0.5.0）

- `set_analysis_mode`: 分析モード切り替え（SwiftUI/Architecture/Testing/Refactoring/General）
- `think_about_analysis`: 思考促進プロンプト

### Tier 2: 高度な機能（計画中）

#### セマンティック解析

- **呼び出しグラフ**: 関数/メソッドの呼び出し関係を追跡
- **依存関係解析**: 型間の依存関係グラフ
- **スコープ解析**: 変数のスコープと有効範囲
- **変数使用箇所**: 特定の変数がどこで使われているか

実装方法:

```swift
// 呼び出しグラフの構築
class CallGraphBuilder: SyntaxVisitor {
    func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind
    func buildGraph() -> CallGraph
}

// 依存関係解析
class DependencyAnalyzer {
    func analyzeDependencies(for type: String) -> [TypeDependency]
    func findUsages(of type: String) -> [UsageLocation]
}
```

#### 型推論（限定的）

- 明示的な型アノテーションの追跡
- 初期化式からの型推論
- 関数戻り値型の推論

制約:

- 完全な型推論は不可能（コンパイラレベルの解析が必要）
- クロージャの複雑な型推論は対象外
- ジェネリクスの具体化は限定的

### Tier 3: 将来の可能性

#### ローカルLLM統合（オプション）

- Ollama等との統合
- コード説明生成
- リファクタリング提案

条件:

- ユーザーが明示的に有効化
- 完全にオプショナル
- デフォルトではオフ

## データモデル

### ProjectMemory

```swift
struct Memory: Codable {
    var lastAnalyzed: Date
    var fileIndex: [String: FileInfo]
    var symbolCache: [String: [SymbolInfo]]
    var importCache: [String: [ImportInfo]]
    var typeConformanceCache: [String: TypeConformanceInfo]
    var notes: [Note]
}

struct FileInfo: Codable {
    let path: String
    let lastModified: Date
    let symbolCount: Int
}

struct SymbolInfo: Codable {
    let name: String
    let kind: String
    let filePath: String
    let line: Int
}

struct ImportInfo: Codable {
    let module: String
    let kind: String?
    let line: Int
}

struct TypeConformanceInfo: Codable {
    let typeName: String
    let typeKind: String
    let filePath: String
    let line: Int
    let superclass: String?
    let protocols: [String]
}
```

保存場所: `~/.swift-selena/clients/{clientId}/projects/{projectName}-{hash}/memory.json`

## パフォーマンス考慮事項

### 解析の最適化

1. **インクリメンタル解析**
   - ファイル単位でのキャッシュ
   - 変更されたファイルのみ再解析
   - ファイル更新日時による自動無効化
2. **遅延評価**
   - 必要な情報のみを解析
   - プロジェクト全体のスキャンは最小限
   - キャッシュがあれば即座に返却
3. **除外ディレクトリ**
   - `.build/`, `.git/`, `.swiftpm/`, `Pods/`, `Carthage/`, `DerivedData/`を自動除外
   - 依存ライブラリの解析をスキップして高速化
4. **エラーハンドリング**
   - ファイル読み込みエラー時のスキップ
   - 構文エラーがあっても処理継続

## セキュリティとプライバシー

### データの取り扱い

- ✅ 全データはローカルに保存
- ✅ ネットワーク通信なし
- ✅ ユーザーのコードは外部に送信されない
- ✅ テレメトリなし

### ファイルアクセス

- プロジェクトディレクトリ配下のみアクセス
- `~/.swift-selena/`にメタデータ保存
- 他のディレクトリへのアクセスなし

## 制限事項

### できること ✅

- ビルド不要での構文解析
- ファイル/コード検索
- シンボル一覧の抽出
- 構造的な情報の取得
- SwiftUI Property Wrapper解析
- Protocol準拠と継承関係の解析
- Extension解析
- Import依存関係の可視化
- 型の継承階層追跡
- XCTestケース検出

### できないこと ❌

- 完全な型推論
- コンパイルエラーの検出
- ジェネリクスの完全な解決
- マクロ展開後のコード解析
- クロスプロジェクト参照（Swift Packageの依存先等）
- セマンティックな等価性の判定（UserとPersonが同じ概念かの判断）

## バージョン情報

**Current Version**: v0.5.0 (2025/10/13)

リリース履歴と今後の開発計画については、以下を参照：
- **[HISTORY.md](../HISTORY.md)** - リリース履歴
- **[Hybrid Architecture Plan](Hybrid-Architecture-Plan.md)** - v0.5.x系開発計画

## 参考資料

- [MCP Protocol Specification](https://modelcontextprotocol.io/)
- [SwiftSyntax Documentation](https://github.com/apple/swift-syntax)
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)

## ライセンス

（プロジェクトのライセンスに従う）

------

**Document Version**: 1.3
**Last Updated**: 2025-10-15
**Maintainer**: Swift-Selena Development Team