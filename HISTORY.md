# Release History

Swift-Selenaのリリース履歴

---

## v0.5.1 - 2025/10/21

### LSP基盤整備

**新規コンポーネント:**
- LSPState Actor - LSP接続状態管理
- LSPClient - SourceKit-LSP通信基盤（JSON-RPC over stdin/stdout）
- 動的ツールリスト生成（LSP状態に応じてツール変更）

**機能:**
- バックグラウンドLSP接続（initialize_project時、非ブロッキング）
- ビルド可能時のみLSP機能を提供（v0.5.2以降）
- グレースフルデグレード（LSP失敗でもSwiftSyntax動作）

**設計判断:**
- BuildChecker削除（直接LSP接続試行で十分）
- Serenaと同じシンプルなアプローチ

---

### ツール削減とクリーンアップ

**削除したツール（-5個）:**
- ❌ read_file → Claude標準Readで完全代替
- ❌ read_lines → Claude標準Readで完全代替
- ❌ read_function_body → read_symbolで代替
- ❌ list_directory → Claude Bash（ls）で完全代替
- ❌ get_project_stats → 価値が低い

**削減理由:**

**パフォーマンス分析:**
- read_file: Swift-Selena = Claude Read（差なし）
- read_lines: コンテキスト効率は限定的（結局全体を見る）
- list_directory: ls コマンドと同じ（差なし）

**正確性分析:**
- 全て同じ結果（ファイルシステム操作）

**代替可能性:**
- read_file, read_lines, list_directory: Claude標準機能で100%代替
- read_function_body: read_symbol(symbol_path: "Class/method")で代替
- get_project_stats: search_notesで十分

**結論:**
- Claude標準機能との重複排除
- Swift-Selenaは「Swift解析」に特化
- メンテナンス負担削減

**ツール総数**: 22個 → **17個**

---

### 今後の方針転換

**LSPツール追加の再考:**

**従来の計画:**
- LSPツール5個を新規追加（find_symbol_references, get_symbol_info等）
- ツール総数: 22個 → 27個

**新しい方針:**
- 既存ツールをLSPで強化（新規ツール追加を最小化）
- list_symbols → LSP利用時は型情報付き
- get_type_hierarchy → LSP利用時はfind_overrides情報も含む

**新規追加するのは:**
- find_symbol_references のみ（既存機能にない）

**最終ツール数**: 17個 → 18個（+1個のみ）

**詳細**: docs/tool_design/内の各設計書を参照

---

## v0.5.0 - 2025/10/13

### 新機能

**5つの新しいツールを追加（合計22個）:**

1. **set_analysis_mode** - 分析モード切り替え
   - SwiftUI / Architecture / Testing / Refactoring / General モード
   - モード別のツール使用ガイダンスを提供
   - Serenaのモード機能を参考に実装

2. **read_symbol** - シンボル単位読み取り
   - ファイル全体を読まずに特定シンボルのみ取得
   - 大規模ファイル（5000行以上）でコンテキスト効率を大幅改善

3. **list_directory** - ディレクトリ一覧
   - ファイルとディレクトリの一覧表示
   - 再帰的検索オプション

4. **read_file** - 汎用ファイル読み取り
   - あらゆる種類のファイルを読み取り
   - 設定ファイル、JSONファイル等に対応

5. **think_about_analysis** - 思考促進ツール
   - 分析の進捗確認を促すプロンプト
   - 分析の質を向上

### 改善

- ツール総数: 17個 → 22個
- モード機能により、タスクに応じた最適なツール使用をガイド
- 大規模プロジェクト対応を強化

### 技術スタック

- SwiftSyntax 602.0.0
- MCP Swift SDK 0.10.2
- Swift 5.9+

---

## v0.4.2 - 2025/10/06

### 機能

- **17個のツール提供**
  - プロジェクト管理: 1個
  - ファイル検索: 2個
  - SwiftSyntax解析: 9個
  - 効率的な読み取り: 2個
  - プロジェクトメモ: 3個

- **SwiftUI特化機能**
  - Property Wrapper解析（@State, @Binding等）
  - Protocol準拠と継承関係の解析
  - Extension解析

- **キャッシュシステム（v0.4.0）**
  - ファイル単位キャッシュ
  - 自動ガベージコレクション
  - ファイル変更検知による自動無効化

- **複数クライアント対応**
  - MCP_CLIENT_IDによるデータ分離
  - Claude CodeとClaude Desktopの同時使用

### 技術スタック

- SwiftSyntax 602.0.0
- MCP Swift SDK 0.10.2
- CryptoKit（プロジェクトパスハッシュ）
- swift-log

### アーキテクチャ

- ビルド不要で動作（SwiftSyntaxベース）
- 完全ローカル実行
- Stdioトランスポート

---

## v0.4.0 - 2025/10/04

### 主な変更

- ✅ ファイル単位キャッシュシステム（Cache/ディレクトリ）
- ✅ CacheManager, FileCacheEntry, CacheGarbageCollector実装
- ✅ 自動ガベージコレクション（1時間 OR 100リクエスト）
- ✅ ファイル変更検知による自動キャッシュ無効化

### 破壊的変更

- キャッシュ形式の変更（memory.json → cache.json）
- 既存キャッシュの再構築が必要

---

## v0.3.0 - 2025/10/03

### 主な変更

- ✅ 基本的なSwiftSyntax解析
- ✅ SwiftUI特化機能
  - Property Wrapper解析
  - Protocol準拠解析
  - Extension解析
- ✅ ファイル/コード検索（除外ディレクトリ対応）
- ✅ Import依存関係解析
- ✅ 型の継承階層解析
- ✅ XCTestケース検出
- ✅ 型使用箇所の追跡（find_type_usages）
- ✅ コードベースリファクタリング（ファイル分割）
- ✅ 複数クライアント対応（プロジェクトパスハッシュ方式）

**提供ツール数**: 17個

---

## 今後の開発計画

詳細な開発計画については、以下のドキュメントを参照してください：

**[Hybrid Architecture Plan](docs/Hybrid-Architecture-Plan.md)**
- v0.5.0-0.5.4: LSP統合ロードマップ
- ハイブリッドアーキテクチャの詳細設計

---

**Last Updated**: 2025-10-11
