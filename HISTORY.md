# Release History

Swift-Selenaのリリース履歴

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
