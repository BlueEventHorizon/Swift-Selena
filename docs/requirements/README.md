# Swift-Selena 要件定義書

このディレクトリには、Swift-Selenaの全機能に関する要件定義書が含まれています。

---

## 📚 要件定義書一覧

### REQ-001: Swift-Selena全体要件定義
**対象:** プロジェクト全体
**内容:**
- プロジェクトの存在意義
- 解決する課題（ビルド不要、プライバシー、パフォーマンス）
- ターゲットユーザー
- 競合比較（Serena, SourceKit-LSP, Xcode）
- 6つの主要ユースケース
- リリース計画

**ファイル:** [REQ-001_Swift_Selena_Overall_Requirements.md](REQ-001_Swift_Selena_Overall_Requirements.md)

---

### REQ-002: v0.5.x LSP統合要件
**対象:** v0.5.1〜v0.5.5（LSP統合フェーズ）
**内容:**
- なぜLSP統合が必要か（SwiftSyntaxの限界、正確な参照検索の必要性）
- ハイブリッドアーキテクチャの必然性
- v0.5.1〜v0.5.5各バージョンの要件と成功基準
- LSPツールのユースケース
- グレースフルデグレードの重要性

**ファイル:** [REQ-002_LSP_Integration_v0.5.x.md](REQ-002_LSP_Integration_v0.5.x.md)

---

### REQ-003: コア機能要件
**対象:** 全18ツール
**内容:**
- ツール分類とカテゴリ
- 各ツールの要件（なぜ必要か、何ができるか、どう使うか）
- ツール間の関係
- 典型的なワークフロー3パターン
- ツール選択ガイド

**ファイル:** [REQ-003_Core_Features_Requirements.md](REQ-003_Core_Features_Requirements.md)

---

## 🎯 要件定義の目的

### 1. プロジェクトの方向性明確化
**何のために作るのか、誰のために作るのか**を明確にする

### 2. 機能の必要性の説明
**なぜこの機能が必要か**を技術者・非技術者両方が理解できるように

### 3. 成功の定義
**何を持って成功とするか**を定量的・定性的に定義

### 4. スコープの管理
**何を実装し、何を実装しないか**を明確に区別

---

## 📊 要件マッピング

### プロジェクト全体の要件階層

```
REQ-001: 全体要件
    ├─ FR-001: ビルド非依存の解析
    ├─ FR-002: Swift特化解析
    ├─ FR-003: ローカル完結性
    ├─ FR-004: MCP統合
    ├─ FR-005: 永続化とキャッシュ
    └─ FR-006: LSP統合
        │
        └─ REQ-002: LSP統合要件
            ├─ FR-LSP-001: find_symbol_references（v0.5.2）
            ├─ FR-LSP-002: list_symbols強化（v0.5.4）
            ├─ FR-LSP-003: get_type_hierarchy強化（v0.5.4）
            ├─ FR-LSP-004: get_call_hierarchy（v0.5.5）
            ├─ NFR-LSP-001: グレースフルデグレード
            ├─ NFR-LSP-002: 動的ツールリスト
            ├─ NFR-LSP-003: LSP接続の安定性
            └─ NFR-LSP-004: デバッグ可能性

REQ-003: コア機能要件
    ├─ プロジェクト管理（initialize_project）
    ├─ ファイル検索（find_files, search_code）
    ├─ シンボル解析（list_symbols, find_symbol_definition, read_symbol）
    ├─ SwiftUI解析（list_property_wrappers, list_protocol_conformances, list_extensions）
    ├─ 依存関係解析（analyze_imports, get_type_hierarchy, find_test_cases, find_type_usages）
    ├─ 分析モード（set_analysis_mode, think_about_analysis）
    ├─ プロジェクトノート（add_note, search_notes）
    └─ LSP機能（find_symbol_references）
```

---

## 🔍 要件の読み方

### 開発者向け
**実装前に読むべき文書:**
1. REQ-003: 実装するツールの要件を確認
2. REQ-002: LSP統合の場合、プロトコル要件を確認
3. REQ-001: 全体設計原則を確認

### ユーザー向け
**Swift-Selenaの理解:**
1. REQ-001: Swift-Selenaとは何か、なぜ必要か
2. REQ-003: どんなツールがあるか、どう使うか

### レビュアー向け
**機能追加の妥当性判断:**
1. REQ-001の設計原則に合致しているか
2. 既存要件と矛盾していないか
3. スコープ外ではないか

---

## ✅ 要件定義の完全性

### カバー範囲

**実装済み機能:**
- ✅ 全18ツールの要件定義（REQ-003）
- ✅ v0.5.1〜v0.5.3の要件と検証結果（REQ-002）
- ✅ プロジェクト全体の要件（REQ-001）

**計画中の機能:**
- ✅ v0.5.4〜v0.5.5の要件（REQ-002）
- ✅ v0.6.0以降の概要（REQ-001）

---

## 📝 要件定義書の保守

### 更新タイミング

**機能追加時:**
- 新機能の要件をREQ-XXXに追記
- 必要なら新しいREQ-XXXを作成

**バージョンリリース時:**
- 成功基準の達成状況を記録
- 学んだ教訓を反映

**設計変更時:**
- 要件への影響を評価
- REQ文書を更新

---

## 🎓 学んだ教訓（CONVERSATION_HISTORYより）

### 要件定義の重要性

**v0.5.2/v0.5.3開発での教訓:**

1. **プロトコル仕様の完全理解**
   - initialized通知の欠落 → LSPクラッシュ
   - 要件定義で「LSPプロトコル準拠」を明記すべきだった

2. **デバッグ環境は最優先**
   - 「デバッグできないと何も進められない」
   - 要件に「デバッグ可能性」を含めるべき

3. **段階的実装とスコープ管理**
   - 1バージョン1機能に絞る
   - 要件定義でスコープを明確に

---

## 📖 関連ドキュメント

### 設計文書
- Swift-Selena Design.md: アーキテクチャ設計
- Hybrid-Architecture-Plan.md: LSP統合詳細設計
- PLAN.md: 開発計画

### 実装文書
- DES-007: LSP基盤設計（v0.5.1）
- DES-008: DebugRunner設計
- DES-009: list_symbols/get_type_hierarchy強化設計（v0.5.4）

### 履歴
- HISTORY.md: リリース履歴
- CONVERSATION_HISTORY.md: 開発会話履歴

---

## 🚀 次のステップ

### v0.5.4実装準備
1. ✅ REQ-002でv0.5.4要件確認
2. ✅ REQ-003でlist_symbols/get_type_hierarchy要件確認
3. → DES-009設計書作成
4. → 承認後、実装開始

---

**Document Version**: 1.0
**Created**: 2025-10-24
**Last Updated**: 2025-10-24
**Purpose**: Swift-Selena要件定義の索引と概要
