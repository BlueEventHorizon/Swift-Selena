# Swift-Selena 設計書

このディレクトリには、Swift-Selenaの全設計書が含まれています。

---

## 📐 設計書一覧

### DES-101: システムアーキテクチャ設計書
**対象:** Swift-Selena全体のシステム設計
**内容:**
- システム概要と構成図
- コアコンポーネント詳細（SwiftMCPServer, ProjectMemory, LSPState/Client, Analyzer, FileSearcher）
- データフロー（ツール実行、LSP統合、キャッシュ）
- ファイル構成とディレクトリ構造
- 設計原則の実装（ビルド非依存性、ローカル完結性、グレースフルデグレード）
- パフォーマンス設計
- デプロイメント

**ファイル:** [DES-101_System_Architecture.md](DES-101_System_Architecture.md)

**統合元:**
- Swift-Selena Design.md
- Hybrid-Architecture-Plan.md（アーキテクチャ部分）

---

### DES-102: LSP統合設計書
**対象:** v0.5.1〜v0.5.5（LSP統合フェーズ）
**内容:**
- LSP統合の設計方針（ハイブリッド、グレースフルデグレード）
- v0.5.x系実装ロードマップ
- LSPプロトコル完全仕様（initialize, initialized, didOpen, references, documentSymbol, typeHierarchy）
- LSPClient完全実装
- エラーハンドリング戦略
- デバッグ環境設計（FileLogHandler, DebugRunner）
- 動的ツールリスト設計
- 学んだ教訓（プロトコル理解、デバッグ環境、段階的実装）

**ファイル:** [DES-102_LSP_Integration_Design.md](DES-102_LSP_Integration_Design.md)

**統合元:**
- DES-007（LSP基盤、v0.5.1）
- DES-008 DebugRunner
- DES-009（list_symbols/get_type_hierarchy強化、v0.5.4）
- Hybrid-Architecture-Plan.md（LSP部分）

---

### DES-103: ツール実装設計書
**対象:** 全18ツールの実装詳細
**内容:**
- ツール実装の標準パターン
- MCPToolプロトコル
- LSP強化パターン
- カテゴリ別実装詳細（18ツール全て）
- SwiftSyntax Visitor実装パターン
- ツールヘルパー（ToolHelpers, Constants）
- 新ツール追加ガイド
- テスト方針
- パフォーマンス最適化
- コーディング規約

**ファイル:** [DES-103_Tool_Implementation_Design.md](DES-103_Tool_Implementation_Design.md)

**新規作成**（既存ツール実装の暗黙知を明文化）

---

## 🗺️ 設計書マップ

### 階層構造

```
DES-101: システムアーキテクチャ（全体像）
    ├─ コアコンポーネント
    │   ├─ SwiftMCPServer
    │   ├─ ProjectMemory
    │   ├─ SwiftSyntaxAnalyzer
    │   ├─ FileSearcher
    │   └─ LSPState/LSPClient ───┐
    │                            │
    ├─ データフロー              │
    └─ 設計原則                  │
                                 │
DES-102: LSP統合設計 ←──────────┘
    ├─ LSPプロトコル実装
    ├─ LSPClient完全仕様
    ├─ デバッグ環境
    └─ v0.5.1〜v0.5.5ロードマップ
         │
         ├─ v0.5.1: 基盤
         ├─ v0.5.2: find_symbol_references
         ├─ v0.5.3: 安定化
         ├─ v0.5.4: ツール強化 ───┐
         └─ v0.5.5: 追加機能      │
                                  │
DES-103: ツール実装設計 ←────────┘
    ├─ 18ツールの実装詳細
    ├─ Visitor実装パターン
    ├─ LSP強化パターン
    └─ 新ツール追加ガイド
```

---

## 📖 設計書の読み方

### 新規参画者向け

**1日目: 全体理解**
- DES-101を読む（システム全体像）
- 特に「システム概要」「設計原則」を重点的に

**2日目: 詳細理解**
- DES-103を読む（ツール実装）
- 興味のあるツールの実装を深く

**3日目以降: 必要に応じて**
- DES-102を読む（LSP統合、必要なら）

---

### 機能追加時

**新しいSwiftSyntaxツール追加:**
1. REQ-003で要件確認
2. DES-103「新ツール追加ガイド」参照
3. 実装

**LSP機能追加:**
1. REQ-002で要件確認
2. DES-102「LSPClient完全仕様」参照
3. DES-102「LSPプロトコル実装」でパターン確認
4. 実装

---

### バグ修正時

**クラッシュ・エラー:**
1. DES-102「エラーハンドリング戦略」確認
2. DES-102「デバッグ環境」でログ確認方法
3. DebugRunnerで再現テスト

**パフォーマンス問題:**
1. DES-101「パフォーマンス設計」確認
2. DES-103「パフォーマンス最適化」でキャッシュ戦略確認

---

## 🔗 関連ドキュメント

### 要件定義
- [REQ-001](../requirements/REQ-001_Swift_Selena_Overall_Requirements.md): 全体要件
- [REQ-002](../requirements/REQ-002_LSP_Integration_v0.5.x.md): LSP統合要件
- [REQ-003](../requirements/REQ-003_Core_Features_Requirements.md): コア機能要件

### 計画・履歴
- [PLAN.md](../tool_design/PLAN.md): 開発計画（v0.5.x〜v1.0）
- [HISTORY.md](../../HISTORY.md): リリース履歴
- [CONVERSATION_HISTORY.md](../tool_design/CONVERSATION_HISTORY.md): 開発会話履歴

### 参考資料
- [MCP-Implementation-Guide.md](../MCP-Implementation-Guide.md): MCP実装ガイド
- [MCP-SDK-Deep-Dive.md](../MCP-SDK-Deep-Dive.md): MCP SDK詳細

### 将来の機能（v0.6.0+）
- [DES-004](../tool_design/DES-004_swift_toc_generation_design.md): ToC生成（廃止予定）
- [DES-005](../tool_design/DES-005_code_header_generation_design.md): Code Header生成
- [DES-006](../tool_design/DES-006_code_header_db_design.md): Code Header DB

---

## 📋 設計書の保守

### 更新タイミング

**機能追加時:**
- 新機能の設計をDES-XXXに追記
- 必要なら新DES-XXXを作成

**バージョンリリース時:**
- 実装結果を設計書に反映
- 学んだ教訓を追記

**アーキテクチャ変更時:**
- DES-101を更新
- 影響範囲を他の設計書に反映

---

## ✅ 設計書の完全性

### カバー範囲

**実装済み（v0.5.3）:**
- ✅ 全18ツールの設計（DES-103）
- ✅ LSP統合設計（DES-102）
- ✅ システムアーキテクチャ（DES-101）

**計画中:**
- ✅ v0.5.4: list_symbols/get_type_hierarchy強化（DES-102）
- ✅ v0.5.5: call_hierarchy等（DES-102）
- ✅ v0.6.0以降: Code Header DB（DES-004, 005, 006）

---

## 🎯 設計の完全性検証

### チェックリスト

**アーキテクチャ:**
- ✅ 全コンポーネントがDES-101に記述されている
- ✅ データフローが明確
- ✅ ファイル構成が明記

**LSP統合:**
- ✅ プロトコルフロー完全記述（DES-102）
- ✅ 全LSP APIの仕様記述
- ✅ エラーハンドリング網羅

**ツール実装:**
- ✅ 全18ツールの実装詳細（DES-103）
- ✅ Visitor実装パターン記述
- ✅ 新ツール追加ガイド完備

---

## 🚀 次のステップ

### v0.5.4実装準備
1. ✅ REQ-002でv0.5.4要件確認
2. ✅ DES-102でLSP実装パターン確認
3. ✅ DES-103でツール強化パターン確認
4. → 実装開始

---

**Document Version**: 1.0
**Created**: 2025-10-24
**Last Updated**: 2025-10-24
**Purpose**: Swift-Selena設計書の索引と概要
