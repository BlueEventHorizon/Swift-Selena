# Swift-Selena 開発計画

**作成日**: 2025-10-21
**対象**: v0.5.x - v1.0
**現在バージョン**: v0.5.5

---

## 概要

Swift-SelenaのSwiftSyntaxベースの静的解析に、LSP統合とCode Header DB等の高度な機能を段階的に追加し、大規模プロジェクトでも実用的なSwift解析ツールを実現する。

---

## 設計原則

1. **ビルド非依存性の維持**: ビルドエラーがあっても基本機能は動作
2. **ローカル完結性**: 外部サーバーへの接続なし、プライバシー保護
3. **段階的強化**: SwiftSyntax（ベースライン）+ LSP（オプション強化）
4. **運用の現実**: メンテナンスフリー、自動更新

---

## ロードマップ

### v0.5.0（✅ 完了 - 2025/10/13）

**新機能:**
- 5つの新ツール（合計22ツール）
  - set_analysis_mode（分析モード切り替え）
  - read_symbol（シンボル単位読み取り）
  - list_directory（ディレクトリ一覧）
  - read_file（汎用ファイル読み取り）
  - think_about_analysis（思考促進）

**リファクタリング:**
- SwiftMCPServer.swift: 1,123行 → 250行（78%削減）
- ツールファイル分割（22ツール、10カテゴリ）
- MCPToolプロトコル導入

**バグ修正:**
- find_files パターンマッチング修正

**詳細**: HISTORY.md、docs/tool_design/v0.5.0-*.md参照

---

### v0.5.1（✅ 完了 - 2025/10/21）

**LSP基盤整備:**
- LSPState Actor、LSPClient実装
- 動的ツールリスト生成
- バックグラウンドLSP接続（非ブロッキング）

**ツール削減:**
- 22個 → 17個（-5個）
- Claude標準機能との重複排除

**設計判断:**
- BuildChecker削除（直接LSP接続試行で十分）
- Serenaと同じシンプルなアプローチ

**詳細**: HISTORY.md、docs/tool_design/DES-007参照

---

### v0.5.2（✅ 完了 - 2025/10/21）

**実装内容:**

1. **find_symbol_references**（新規LSPツール）
   - LSPClient.findReferences()を使用した正確な参照検索
   - ファイルパス + 行 + 列の位置ベース検索
   - LSP利用可能時のみツールリストに表示
   - LSP利用不可時: 代替ツール（find_type_usages, search_code）を案内

**技術詳細:**
- FindSymbolReferencesTool.execute()にlspStateパラメータ追加
- SwiftMCPServerからlspStateを渡す
- LSPClient経由でtextDocument/referencesリクエスト送信
- 0-indexed ↔ 1-indexed変換
- MCPToolプロトコル準拠のためのラッパー実装

**ツール総数:**
- ビルド不可: 17個（SwiftSyntaxのみ）
- ビルド可能: 18個（+find_symbol_references）

**設計判断:**
- list_symbols強化、get_type_hierarchy強化はv0.5.3に延期
- 理由: LSP documentSymbol統合に追加実装時間が必要（1-2時間）
- v0.5.2は基本的なLSP機能（参照検索）に集中

**工数**: 30分

**詳細**: commits 7cfd60c, cfdd1eb

---

### v0.5.3（✅ 完了 - 2025/10/24）

**目標**: LSP安定化とデバッグ機能整備

**実装内容:**

1. **LSPプロトコル完全準拠**
   - initialized通知追加
   - textDocument/didOpen実装
   - initializeレスポンス読み捨て
   - LSPプロトコルフロー完全実装

2. **LSP安定化修正**
   - SIGPIPE対策（signal(SIGPIPE, SIG_IGN)）
   - Content-Length計算修正
   - エラーハンドリング強化
   - プロセス状態チェック

3. **デバッグ機能**
   - FileLogHandler（~/.swift-selena/logs/server.log）
   - DebugRunner（プロセス内自動テスト、#if DEBUG）
   - LSPState診断機能

**検証結果:**
- find_symbol_references: 安定動作、参照検出成功（3-34件）
- 5回連続実行でクラッシュなし

**設計判断:**
- list_symbols強化、get_type_hierarchy強化はv0.5.4に延期
- 理由: LSP基盤の安定化を優先

**ツール総数:** 18個（変更なし）

**詳細**: HISTORY.md v0.5.3セクション、docs/tool_design/DES-008参照

---

### v0.5.4（✅ 完了 - 2025/10/26）

**目標**: list_symbols、get_type_hierarchyにLSP型情報を統合

**実装内容:**

1. **LSPClient拡張**
   - documentSymbol() - textDocument/documentSymbol API
   - typeHierarchy() - textDocument/prepareTypeHierarchy API
   - LSPDocumentSymbol, LSPTypeHierarchy構造体追加

2. **list_symbols強化**（既存ツール）
   - executeWithLSP()メソッド追加
   - LSP版: 型情報付き表示（例：`[Method] save: func save() throws`）
   - SwiftSyntax版: 従来通り
   - symbolKindToString()でLSP SymbolKind変換

3. **get_type_hierarchy強化**（既存ツール）
   - executeWithLSP()メソッド追加
   - LSP版: Type Detail追加（例：`Type Detail: class ProjectMemory`）
   - SwiftSyntax版: 従来通り
   - グレースフルデグレード完全実装

**実装完了:**
- ✅ LSPClient拡張（documentSymbol, typeHierarchy）
- ✅ 階層構造対応（children再帰処理）
- ✅ 除外ディレクトリ対応（263ファイル完全一致）
- ✅ Import空ファイル対応
- ✅ ログJST表示
- ✅ グレースフルデグレード完璧

**既知の問題（v0.5.5に延期）:**
- △ LSP非同期通知混入（publishDiagnostics）
- △ documentSymbol/typeHierarchy不安定（フォールバック動作）
- ✅ 実害なし（SwiftSyntax版で完全動作）

**テスト結果:**
- ✅ ContactBプロジェクト: 全ツール完全一致検証
- ✅ find_symbol_references: 動作
- ✅ グレースフルデグレード完璧

**ツール総数:**
- ビルド不可: 17個
- ビルド可能: 18個
- 強化ツール: 2個（実装済み、v0.5.5で安定化）

**工数**: 約5時間（実装90分 + テスト・修正3.5時間）

**詳細**: CONVERSATION_HISTORY.md v0.5.4セクション参照

---

### v0.5.5（✅ 完了 - 2025/10/27）

**目標**: LSP安定化、MCP基盤修正、find_symbol_references削除判断

**実装内容:**

1. **新機能: search_files_without_pattern**
   - grep -L相当、「ないものを探す」検索
   - Code Header未作成ファイル検出
   - Import未記述ファイル発見
   - 統計情報表示

2. **重要なバグ修正（6件）:**
   - 正規表現マルチラインモード（`.anchorsMatchLines`追加）
   - ゾンビプロセス（`server.waitUntilCompleted()`でEOF待機）
   - 本番環境汚染（`swift-selena-debug`別名登録）
   - LSP非同期通知混入（Content-Length正確処理、publishDiagnosticsスキップ）
   - LSPState単一プロジェクト（Dictionary管理で複数プロジェクト対応）
   - initialize_projectバックグラウンド（同期待機、LSP接続完了後にreturn）

3. **find_symbol_references削除判断:**
   - 調査結果: Swift Package（✅動作）、Xcodeプロジェクト（❌常に0件）
   - 原因: SourceKit-LSP Issue #730（Xcodeプロジェクト未サポート）
   - 決断: 削除（約270行）、代替手段（find_type_usages）を推奨
   - 理由: 動作環境が限定的、全プロジェクトタイプで動作する構成を優先

**重要な知見:**
- MCP仕様: `server.waitUntilCompleted()`必須、無限ループは不要
- LSP制限: Xcodeプロジェクトでは参照検索不可、documentSymbol/typeHierarchyは動作
- 開発版と本番版の完全分離: 別名登録で本番環境汚染を防止

**ツール総数:**
- ビルド不可: 17個
- ビルド可能: 18個（find_symbol_references削除により減少）

**工数**: 約3日（バグ修正、調査、判断）

**詳細**: LATEST_CONVERSATION_HISTORY.md、docs/MCP_LSP_LEARNINGS.md参照

---

### v0.6.0（Code Header DB）

**目標**: Code Headerフォーマットを内部DB化し、高速な意図ベース検索を実現

**実装内容:**

1. **CodeHeaderParser**（Sources/CodeHeaderParser.swift）
   - [Code Header Format]マーカー検出
   - 目的・主要機能・含まれる型・関連型を抽出
   - エラー耐性のあるパース

2. **ProjectMemory拡張**
   - codeHeaderCache追加
   - DB永続化

3. **search_code_headers ツール**（統合検索）
   - 目的・機能・型を自然言語で検索
   - sectionパラメータ（purpose/feature/type/all）
   - layerパラメータ（Tools/Library/Domain等）
   - NaturalLanguageで形態素解析
   - キーワードマッチング

4. **get_code_header_stats ツール**
   - Code Header適用率
   - 層別統計
   - 未適用ファイルリスト

**検索精度:**
- Phase 1: 70-80%（形態素解析）
- Phase 2: 80-85%（類義語辞書、v0.6.1）
- Phase 3: 90%+（ベクトル検索、v0.7.0、要検証）

**Apple Foundation Models使用:**
- NaturalLanguage: 形態素解析、品詞タグ付け
- CreateML: ベクトル埋め込み（Phase 3、検証後）

**ツール総数**: +2個（search_code_headers, get_code_header_stats）

**工数**: 1週間

**リリース目標**: 2026年1月

**詳細**: docs/tool_design/DES-006_code_header_db_design.md参照

---

### v0.6.1（検索精度向上）

**目標**: 類義語辞書で検索精度を80-85%に向上

**実装内容:**

1. **類義語辞書**
   - 手動辞書作成（フォーマット/整形/表示等）
   - 使用ログからの学習機能

2. **クエリ拡張**
   - 「綺麗に表示」→「フォーマット」「整形」等に展開
   - 英語・日本語混在対応

**工数**: 1-2日

**リリース目標**: 2026年1月

---

### v0.6.2（MCP Prompts Capability移行）

**目標**: set_analysis_mode, think_about_analysisを正しいMCP Prompts実装に移行

**実装内容:**

1. **Prompts Capability有効化**
   ```swift
   capabilities: .init(
       tools: .init(),
       prompts: .init()  // 追加
   )
   ```

2. **ListPrompts / GetPrompt ハンドラ実装**
   - swiftui-analysis
   - architecture-analysis
   - testing-analysis
   - refactoring-analysis
   - general-analysis

3. **既存ツール削除**
   - set_analysis_mode → Prompts機能に置き換え
   - think_about_analysis → Prompts機能に置き換え

**ツール総数**: 19-20個 → 17-18個（-2個、Prompts機能に移行）

**工数**: 2-3日

**リリース目標**: 2026年2月

**詳細**: docs/tool_design/Hybrid-Architecture-Plan.md Section 21参照

---

### v0.6.3（コメント検索機能）

**目標**: SwiftSyntaxのTriviaを使った正確なコメント検索

**実装内容:**

1. **CommentVisitor**（Sources/Visitors/CommentVisitor.swift）
   - Triviaからコメント抽出
   - コメント種別識別（LineComment/DocComment/BlockComment）

2. **search_comments ツール**
   - TODO/FIXME/MARK検索
   - ドキュメントコメント検索
   - 複数行コメント対応
   - コメント種別フィルタ

**ツール総数**: +1個

**工数**: 2-3日

**リリース目標**: 2026年2月

**詳細**: docs/tool_design/Hybrid-Architecture-Plan.md Section 22参照

---

### v0.7.0（ベクトル検索）

**目標**: 意味的類似度検索の実現（精度90%+）

**前提条件:**
- CreateMLの日本語埋め込み精度検証
- 精度が不十分ならPhase 2（類義語辞書）で停止

**実装内容:**

1. **CreateML / CoreML統合**
   - NLEmbeddingでテキストベクトル化
   - Code Headerの事前ベクトル化
   - コサイン類似度検索

2. **search_code_headers拡張**
   - セマンティック検索オプション
   - 類似度スコア表示

**代替案（CreateML精度不足の場合）:**
- Apple Intelligence API（M1+）
- ローカルLLM（Ollama）の埋め込みAPI

**工数**: 5-7日（検証含む）

**リリース目標**: 2026年3月（検証結果次第）

**詳細**: docs/tool_design/DES-006_code_header_db_design.md Section 22参照

---

### v0.8.0（統計・分析機能）

**目標**: コード品質メトリクスとプロジェクト分析

**実装内容:**

1. **コード品質メトリクス**
   - ファイルサイズ分布
   - クラス複雑度
   - テストカバレッジ推定
   - ドキュメント品質スコア

2. **依存関係分析の強化**
   - 循環依存の検出
   - レイヤー違反の検出
   - モジュール結合度の測定

3. **レポート生成**
   - プロジェクト健全性レポート
   - リファクタリング推奨事項
   - mermaid図の自動生成

4. **get_tool_usage_stats**（ツール使用統計）
   - ツール呼び出し回数
   - 成功率、エラー率
   - 平均実行時間
   - ※設計見直し後に実装（ProjectMemory外で管理、stats.json分離）

**ツール総数**: +1個（get_tool_usage_stats）

**工数**: 2週間

**リリース目標**: 2026年4月

---

### v1.0.0（安定版リリース）

**目標**: 本番環境での使用に耐える安定版

**完了条件:**

1. **機能完成度**
   - 全計画機能の実装完了
   - LSP統合の安定動作
   - Code Header DB運用実績

2. **品質保証**
   - ユニットテストカバレッジ80%+
   - 統合テスト完備
   - 大規模プロジェクト（1000+ファイル）で検証

3. **ドキュメント完備**
   - 全ツールのドキュメント
   - チュートリアル
   - トラブルシューティングガイド

4. **パフォーマンス**
   - 1000ファイルプロジェクトで10秒以内
   - メモリ使用量100MB以下
   - クラッシュゼロ

**工数**: 1ヶ月（最終調整、テスト、ドキュメント）

**リリース目標**: 2026年6月

---

## 機能別計画

### 1. LSP統合（v0.5.1-0.5.5）

**目的**: ビルド可能なプロジェクトで型情報ベースの高度な機能を提供

**段階:**
- v0.5.1: 基盤整備（LSPState, LSPClient）✅
- v0.5.2: find_symbol_references新規実装 ✅
- v0.5.3: list_symbols/get_type_hierarchy強化
- v0.5.4: get_call_hierarchy等（1-2ツール）
- v0.5.5: 最適化（レスポンスパース、エラーハンドリング、パフォーマンス）

**最終ツール数**:
- ビルド不可: 17個（SwiftSyntaxのみ）
- ビルド可能: 19-20個（+2-3個のLSPツール）
- 強化ツール: 2個（list_symbols, get_type_hierarchy）

**詳細設計**: docs/tool_design/Hybrid-Architecture-Plan.md

---

### 2. Code Header DB（v0.6.0-0.6.1）

**目的**: Code Headerを内部DB化し、高速な意図ベース検索を実現

**段階:**
- v0.6.0: DB構築、search_code_headers実装
- v0.6.1: 類義語辞書で精度向上

**検索速度**: 5分 → 0.1秒（3000倍高速化）
**検索精度**: 80-85%（類義語辞書込み）

**詳細設計**: docs/tool_design/DES-006_code_header_db_design.md

---

### 3. Prompts機能（v0.6.2）

**目的**: 分析モード機能を正しいMCP Prompts実装に移行

**変更:**
- Tools/Prompts/ の2ツールを削除
- MCP Prompts Capabilityで再実装

**詳細設計**: docs/tool_design/Hybrid-Architecture-Plan.md Section 21

---

### 4. コメント検索（v0.6.3）

**目的**: SwiftSyntax Triviaによる正確なコメント検索

**実装:**
- search_comments ツール
- TODO/FIXME/MARK専用検索
- 複数行コメント対応

**詳細設計**: docs/tool_design/Hybrid-Architecture-Plan.md Section 22

---

### 5. ベクトル検索（v0.7.0）

**目的**: 意味的類似度検索で90%+の精度

**前提**: CreateMLの日本語精度検証

**実装:**
- Apple NLEmbedding使用
- コサイン類似度検索

**詳細設計**: docs/tool_design/DES-006_code_header_db_design.md Section 22

---

### 6. 統計・分析機能（v0.8.0）

**目的**: コード品質メトリクスとツール使用統計

**実装:**
- get_tool_usage_stats（設計見直し後）
- コード品質メトリクス
- 依存関係分析
- レポート生成

---

## 技術スタック

### 現在（v0.5.1）

| 技術 | 用途 |
|------|------|
| Swift 5.9+ | 実装言語 |
| SwiftSyntax 602.0.0 | 構文解析 |
| MCP Swift SDK 0.10.2 | MCPプロトコル |
| CryptoKit | プロジェクトパスハッシュ |
| swift-log | ロギング |
| SourceKit-LSP | 型情報ベース解析（v0.5.1+） |

### 追加予定

| 技術 | バージョン | 用途 |
|------|----------|------|
| NaturalLanguage | macOS標準 | v0.6.0: 形態素解析 |
| CreateML | macOS標準 | v0.7.0: ベクトル検索（検証後） |

---

## 実装優先度

### 🔴 優先度: 最高

1. **LSP統合**（v0.5.1-0.5.4）
   - 大規模プロジェクトで必須
   - 完全な参照検索を実現

2. **Code Header DB**（v0.6.0）
   - 意図ベース検索の基盤
   - 開発効率に直結

### 🟡 優先度: 高

3. **検索精度向上**（v0.6.1）
   - 類義語辞書
   - 実用レベルの達成

4. **コメント検索**（v0.6.3）
   - TODO管理に有用
   - 開発体験向上

### 🟢 優先度: 中

5. **Prompts機能移行**（v0.6.2）
   - 概念的に正しい実装
   - 現状でも動作している

6. **ベクトル検索**（v0.7.0）
   - 精度向上（90%+）
   - 検証が前提

### 🔵 優先度: 低

7. **統計・分析機能**（v0.8.0）
   - あれば便利
   - 必須ではない

---

## 成功指標

### v0.5.x系（LSP統合）

| 指標 | 目標値 |
|------|--------|
| ビルド可能プロジェクトでの機能数 | 19-20ツール |
| ビルド不可でも動作 | 17ツール |
| 参照検索精度（LSP） | 95%+ |
| グレースフルデグレード | 100%（LSP失敗でも動作） |

### v0.6.x系（Code Header DB）

| 指標 | 目標値 |
|------|--------|
| 検索速度 | <0.1秒 |
| 検索精度 | 80-85% |
| Code Header適用率 | 80%+ |
| ノイズ削減率 | 95%+ |

### v1.0.0（安定版）

| 指標 | 目標値 |
|------|--------|
| テストカバレッジ | 80%+ |
| 1000ファイルプロジェクト処理時間 | <10秒 |
| メモリ使用量 | <100MB |
| クラッシュ率 | 0% |

---

## リスク管理

### リスク1: LSP統合の複雑さ

**発生確率**: 中
**影響度**: 大
**対策**:
- 段階的実装（v0.5.1-0.5.4）
- グレースフルデグレード必須
- SwiftSyntax機能は常に動作

---

### リスク2: CreateMLの日本語精度不足

**発生確率**: 中（未検証）
**影響度**: 中
**対策**:
- v0.7.0実装前に検証プロジェクト
- 精度不足なら類義語辞書で停止（85%でも十分）
- Apple Intelligence等の代替案検討

---

### リスク3: Code Header生成の定着

**発生確率**: 中（運用依存）
**影響度**: 中
**対策**:
- 新規ファイル追加時のチェックリスト
- get_code_header_statsで可視化
- CI/CDでの自動チェック

---

### リスク4: 実装スケジュールの遅延

**発生確率**: 中
**影響度**: 低
**対策**:
- 段階的リリース（機能ごとにバージョンアップ）
- 優先度による柔軟な調整
- v1.0.0は機能完成度より安定性重視

---

## 開発体制

### 単独開発

**現状**: 1人での開発

**対策**:
- 段階的実装（1機能ずつ）
- 徹底したテスト
- ドキュメント優先

### Claude Code / Serenaの活用

**開発支援:**
- Swift-Selena自身を使った開発
- Serena（汎用）との併用
- ドッグフーディング

---

## マイルストーン

### 2025年Q4（10-12月）

- ✅ v0.5.0完了（10月13日）
- ✅ v0.5.1完了（10月21日）
- ✅ v0.5.2完了（10月21日）
- ✅ v0.5.3完了（10月24日）
- ✅ v0.5.4完了（10月26日）
- ✅ v0.5.5完了（10月27日）
- 次: v0.6.0（Code Header DB）開始予定

### 2026年Q1（1-3月）

- v0.6.0（Code Header DB）
- v0.6.1（類義語辞書）
- v0.6.2（Prompts移行）
- v0.6.3（コメント検索）
- 目標: v0.6.x系完了

### 2026年Q2（4-6月）

- v0.7.0（ベクトル検索、検証次第）
- v0.8.0（統計・分析）
- v1.0.0（安定版リリース）
- 目標: v1.0.0リリース

---

## 参照ドキュメント

### 開発計画

- **[PLAN.md](PLAN.md)**（本文書） - 総合開発計画
- **[HISTORY.md](../../HISTORY.md)** - リリース履歴
- **[CONVERSATION_HISTORY.md](CONVERSATION_HISTORY.md)** - 設計経緯

### 技術設計

- **[Swift-Selena Design](../Swift-Selena%20Design.md)** - アーキテクチャと設計原則
- **[Hybrid-Architecture-Plan](Hybrid-Architecture-Plan.md)** - LSP統合詳細
- **[DES-006](DES-006_code_header_db_design.md)** - Code Header DB詳細
- **[DES-005](DES-005_code_header_generation_design.md)** - Code Header生成

### 比較・調査

- **[Swift-Selena vs Serena](../Swift-Selena-vs-Serena.md)** - Serenaとの比較
- **[MCP SDK Deep Dive](../MCP-SDK-Deep-Dive.md)** - MCP Swift SDK学習ガイド
- **[MCP Implementation Guide](../MCP-Implementation-Guide.md)** - 実装ガイド

---

## 重要な設計決定

### 1. ハイブリッドアーキテクチャ

**決定**: SwiftSyntax（ベースライン）+ LSP（オプション強化）

**理由**:
- ビルド不要の原則を維持
- ビルド可能時は型情報で強化
- グレースフルデグレード

---

### 2. Code Header方式の採用

**決定**: ToCファイル（DES-004）を廃止、Code Headerフォーマット（DES-005）を採用

**理由**:
- AI推論精度: 40% → 100%
- ファイルとの自動同期
- 更新忘れなし

---

### 3. Apple Foundation Modelsの積極活用

**決定**: NaturalLanguage、CreateML（検証後）を使用

**理由**:
- オンデバイス実行
- プライバシー保護
- 追加コストゼロ
- Swift-Selenaの設計原則に合致

---

### 4. ツール統合による最小化

**決定**: 6ツール提案 → 2ツール実装

**理由**:
- 過剰なAPI追加を避ける
- 統合ツールの方が柔軟
- メンテナンス負担削減

---

### 5. 遅延構築方式

**決定**: initialize_project時ではなく、初回検索時にDB構築

**理由**:
- 起動高速化
- 必要な時だけコスト発生
- ユーザー体験向上

---

### 6. get_tool_usage_stats の延期

**決定**: v0.5.2から削除、v0.8.0で再設計後に実装

**理由**:
- 後方互換性の問題（既存memory.jsonとの衝突）
- 統計記録の侵襲性（メインフローへの混入）
- MCPプロトコルの役割逸脱（クライアント側の責務）
- 設計見直しが必要（ProjectMemory外で管理、stats.json分離）

---

## まとめ

Swift-Selenaは以下の進化を遂げる：

**v0.5.0（✅ 完了）**:
- SwiftSyntaxベース、22ツール、ビルド不要

**v0.5.1（✅ 完了）**:
- LSP基盤整備、17ツール、動的ツールリスト

**v0.5.2（✅ 完了）**:
- find_symbol_references実装、18ツール（LSP時）

**v0.5.3（✅ 完了）**:
- LSP安定化、デバッグ機能、参照検索動作確認

**v0.5.4（✅ 完了）**:
- list_symbols/get_type_hierarchy強化、LSP型情報統合

**v0.5.5（✅ 完了）**:
- search_files_without_pattern実装、6つの重要バグ修正、find_symbol_references削除

**v0.5.x系完了（2025 Q4）**:
- SwiftSyntax + LSP、18ツール、ハイブリッド、全プロジェクトタイプ対応

**v0.6.x系（2026 Q1）**:
- Code Header DB、意図ベース検索、精度80-85%

**v0.7.0（2026 Q2）**:
- ベクトル検索、精度90%+（検証次第）

**v1.0.0（2026 Q2）**:
- 安定版、本番環境対応、エコシステム統合

**最終目標**: 大規模プロジェクト（1000+ファイル）でも実用的な、プライバシー保護されたSwift解析ツールの完成

---

**Document Version**: 2.3
**Created**: 2025-10-21
**Last Updated**: 2025-10-28 (v0.5.5完了、CLAUDE.md更新)
