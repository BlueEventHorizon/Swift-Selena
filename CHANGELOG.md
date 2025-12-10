# Release History

Swift-Selenaのリリース履歴

---

## v0.6.1 - 2025/12/06 (開発中)

### ビルド・登録システムのリファクタリング

**Makefile導入:**
- ✅ **make build** - DEBUGビルド
- ✅ **make build-release** - RELEASEビルド
- ✅ **make register-debug** - DEBUG版をこのプロジェクトに登録
- ✅ **make register-release TARGET=/path** - RELEASE版をターゲットに登録
- ✅ **make register-desktop** - Claude Desktopに登録
- ✅ **make unregister-debug/release/desktop** - 登録解除コマンド
- ✅ **make install-client-makefile TARGET=/path** - クライアント用Makefile配布

**ファイル構成変更:**
- `register-*.sh` → `Tools/Scripts/` に移動
- `Makefile`（クライアント用） → `Tools/Client/` に移動
- 新規 `Makefile` でビルド・登録を一元管理

**バグ修正:**
- ✅ **DebugRunner パス修正** - ハードコードされた `/Users/k_terada/...` を動的検出に変更
  - `detectProjectPath()` メソッド追加
  - カレントディレクトリまたは実行ファイルパスから自動検出
- ✅ **ドキュメントのパス修正** - 個人パスをプレースホルダーに置換

**ドキュメント更新:**
- README.md/README.ja.md: Makeコマンド一覧、セットアップ手順更新
- CLAUDE.md: ビルド・登録コマンドをmake形式に更新
- `.claude/commands/create-code-headers.md`: Swift-Selena用にディレクトリ修正

**ツール総数:** 18個（変更なし）

---

## v0.6.0 - (計画中)

### Code Header DB機能（予定）

**計画中の新機能:**
- **search_code_headers** - セマンティック検索でCode Headerを検索
- **get_code_header_stats** - Code Header統計情報

**技術:**
- NLEmbedding（Apple Natural Language）によるベクトル埋め込み
- コサイン類似度による意味検索
- ProjectMemoryへのキャッシュ統合

**詳細**: docs/v0.6.0_implementation_plan.md、docs/requirements/REQ-004_Code_Header_DB_v0.6.x.md参照

---

## v0.5.5 - 2025/10/27

### LSP安定化、MCP基盤修正、新ツール実装

**新機能:**
- ✅ **search_files_without_pattern** - grep -L相当、「ないものを探す」検索
  - Code Header未作成ファイルの検出
  - Import未記述ファイルの発見
  - 統計情報表示（Files checked、Files without pattern、割合）

**重要なバグ修正（6件）:**
1. ✅ **正規表現マルチラインモード** - `.anchorsMatchLines`追加、`^import`が各行にマッチ
2. ✅ **ゾンビプロセス** - `server.waitUntilCompleted()`でEOF正常終了、無限ループ削除
3. ✅ **本番環境汚染** - `swift-selena-debug`別名登録で開発版と本番版を完全分離
4. ✅ **LSP非同期通知混入** - Content-Length正確処理、publishDiagnosticsスキップ
5. ✅ **LSPState単一プロジェクト** - Dictionary管理で複数プロジェクト対応
6. ✅ **initialize_projectバックグラウンド** - 同期待機、LSP接続完了後にreturn

**find_symbol_references削除:**
- 調査結果: Swift Package（✅動作）、Xcodeプロジェクト（❌常に0件）
- 原因: SourceKit-LSP Issue #730（Xcodeプロジェクト未サポート）
- 決断: 削除（約270行）、代替手段（find_type_usages）を推奨
- 理由: 全プロジェクトタイプで動作する構成を優先

**ドキュメント整備:**
- CLAUDE.md: 言語設定、失敗パターンと対策、チェックリスト、ドキュメント更新ルール追加
- PLAN.md: v0.5.5の実装内容を反映
- LATEST_CONVERSATION_HISTORY.md: v0.5.5サマリー作成
- MCP_LSP_LEARNINGS.md: 重要な知見を追加

**重要な知見:**
- MCP仕様: `server.waitUntilCompleted()`必須、無限ループは不要
- LSP制限: Xcodeプロジェクトでは参照検索不可、documentSymbol/typeHierarchyは動作
- 開発版と本番版の完全分離: 別名登録で本番環境汚染を防止

**ツール総数:** 18個（find_symbol_references削除により減少）

**詳細**: docs/LATEST_CONVERSATION_HISTORY.md、docs/MCP_LSP_LEARNINGS.md参照

---

## v0.5.4 - 2025/10/26

### list_symbols、get_type_hierarchyにLSP型情報を統合

**LSPClient拡張:**
- ✅ **documentSymbol()** - textDocument/documentSymbol API実装
- ✅ **typeHierarchy()** - textDocument/prepareTypeHierarchy API実装
- LSPDocumentSymbol、LSPTypeHierarchy構造体追加

**list_symbols強化:**
- executeWithLSP()メソッド追加
- LSP版: 型情報付き表示（例：`[Method] save: func save() throws`）
- SwiftSyntax版: 従来通り（フォールバック）
- symbolKindToString()でLSP SymbolKind変換

**get_type_hierarchy強化:**
- executeWithLSP()メソッド追加
- LSP版: Type Detail追加（例：`Type Detail: class ProjectMemory`）
- SwiftSyntax版: 従来通り（フォールバック）
- グレースフルデグレード完全実装

**実装完了:**
- ✅ LSPClient拡張（documentSymbol, typeHierarchy）
- ✅ 階層構造対応（children再帰処理）
- ✅ 除外ディレクトリ対応（263ファイル完全一致）
- ✅ Import空ファイル対応
- ✅ ログJST表示
- ✅ グレースフルデグレード完璧

**テスト結果:**
- ✅ ContactBプロジェクト: 全ツール完全一致検証
- ✅ find_symbol_references: 動作
- ✅ グレースフルデグレード完璧

**ツール総数:**
- ビルド不可: 17個
- ビルド可能: 18個
- 強化ツール: 2個（list_symbols、get_type_hierarchy）

**詳細**: docs/CONVERSATION_HISTORY.md v0.5.4セクション参照

---

## v0.5.3 - 2025/10/24

### LSP安定化とデバッグ機能

**LSP修正（find_symbol_references完全動作）:**
- ✅ **initialized通知追加** - LSPプロトコル準拠
- ✅ **textDocument/didOpen実装** - ファイルをLSPに通知
- ✅ **initializeレスポンス読み捨て** - バッファクリア
- ✅ **SIGPIPE対策** - signal(SIGPIPE, SIG_IGN)
- ✅ **Content-Length計算修正** - 実際のJSON長を計算
- ✅ **エラーハンドリング強化** - プロセス状態チェック、try-catch

**デバッグ機能:**
- ✅ **FileLogHandler** - ファイルログ出力（~/.swift-selena/logs/server.log）
- ✅ **DebugRunner** - プロセス内自動テストランナー（#if DEBUG、Xcodeデバッガ対応）
- ✅ **LSPState診断機能** - getStatus()メソッド追加

**検証結果:**
- find_symbol_references: 5回連続実行でクラッシュなし
- LSPStateの参照: 3件検出成功
- ProjectMemoryの参照: 34件検出成功
- FindSymbolReferencesTool: 3件検出成功

**技術詳細:**
- LSPプロトコル完全準拠（initialize → initialized → didOpen → requests）
- 開いたファイルをキャッシュ（openedFiles）
- publishDiagnostics通知を正しく処理
- レスポンス解析の詳細ログ出力

**ツール総数:** 18個（変更なし、安定性向上）

**ドキュメント:**
- README.md/README.ja.md: ログ監視方法を追記
- docs/tool_design/DES-008: DebugRunner設計書

**詳細**: docs/tool_design/DES-008_DebugRunner_Design.md参照

---

## v0.5.2 - 2025/10/21

### LSP機能実装

**新規ツール:**
- ✅ **find_symbol_references** - シンボル参照検索（LSP版）
  - 型情報ベースの正確な参照検索
  - textDocument/referencesリクエスト使用
  - ビルド可能時のみ利用可能（動的ツールリスト）
  - LSP利用不可時: find_type_usages, search_code を代替として案内

**技術実装:**
- FindSymbolReferencesTool.execute()にlspStateパラメータ追加
- SwiftMCPServerからlspStateを渡す実装
- MCPToolプロトコル準拠のためのラッパー実装
- 0-indexed ↔ 1-indexed インデックス変換

**ツール総数:**
- ビルド不可: 17個（SwiftSyntaxのみ）
- ビルド可能: 18個（+find_symbol_references）

**設計判断:**
- list_symbols強化、get_type_hierarchy強化はv0.5.3に延期
- 理由: LSP documentSymbol統合に追加実装時間が必要
- v0.5.2は基本的なLSP機能（参照検索）に集中

**削除した機能:**
- ❌ get_tool_usage_stats（v0.8.0に延期）
  - 後方互換性の問題
  - 設計見直しが必要（ProjectMemory外で管理）

**コミット:**
- 7cfd60c: complete FindSymbolReferencesTool
- cfdd1eb: add: FindSymbolReferencesTool

**詳細**: docs/tool_design/PLAN.md v0.5.2セクション参照

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

**Last Updated**: 2025-12-06
