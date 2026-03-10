---
name: planning_workflow
description: 計画書作成ワークフロー
applicable_when:
  - 設計書が完成し、実装計画（{feature}_plan.md）を作成する
  - タスクの優先順位と依存関係を整理する
---

# 計画書作成ワークフロー

**重要**: 計画書は１ファイル作成した時点で人間のレビューを受けること。

**`project/{feature}/plan/` に計画書を作成します**
**フォーマットはマークダウンファイルです**

## 0. プロジェクト文書構造

### ディレクトリ構成

Feature-based 構造でプロジェクト文書を管理します。

```
project/
├── {feature}/          # Feature単位（main, csv_import等）
│   ├── spec/           # 要件定義書
│   ├── design/         # 設計書
│   └── plan/           # 計画書
└── project_toc.yaml    # 検索インデックス（YAML形式）
```

**詳細なディレクトリ構造とID体系**: [spec_format.md](../../format/spec_format.md#project-feature-spec-ディレクトリ構造) を参照

### ファイル命名規則

#### 要件定義書
- **形式**: `{ID}_{機能名}_spec.md`
- **例**: `SCR-001_contact_list_screen_spec.md`

#### 設計書
- **形式**: `DES-XXX_{機能名}_design.md`
- **例**: `DES-001_contact_list_design.md`

#### 計画書
- **形式**: `{feature}_plan.md`
- **例**: `main_plan.md`（Feature名=mainの場合）、`csv_import_plan.md`（Feature名=csv_importの場合）

### 文書間の関係性

```
要件定義書 ←→ 設計書 ←→ タスク
    ↓           ↓         ↓
要件トレーサ  設計トレーサ  実装
ビリティ      ビリティ
マトリクス    マトリクス
```

### 開発フロー

1. **要件定義**: 要件定義書作成（要件ID付与）
2. **設計**: 設計書作成（設計ID付与、要件IDとの紐付け）
3. **計画**: タスク定義（設計IDとの紐付け）
4. **実装**: タスク実行（設計書に基づく実装）

### 文書更新ルール

- **新機能追加時**: 要件定義書 → 設計書 → 計画書の順で作成/更新
- **バグ修正時**:
  - 単発: 直接タスク化（設計書不要）
  - 複数タスク: 設計書作成必須
- **設計変更時**: 設計書更新 → 計画書のマトリクス更新

### ワークフロー開始時の状況確認

ワークフロー開始時に、Featureディレクトリを自動確認して状況を判定する：

| 確認対象 | 判定結果 |
|---------|---------|
| `project/{feature}/plan/{feature}_plan.md` が存在する | 既存計画の更新 |
| `project/{feature}/plan/{feature}_plan.md` が存在しない | 新規計画作成 |
| `project/{feature}/design/` に設計書が存在する | 設計完了、計画書作成可能 |
| `project/{feature}/design/` に設計書が存在しない | 設計書作成から開始 |

**運用**: 状況を自動判定し、ユーザーに報告する。選択肢の提示は不要。

## 1. 開発ルール文書、要件定義書、設計書の取得

- 開発ルール文書（docs/rules/, docs/format/）は  docs-advisor Subagent を使って特定する
- 要件定義書・設計書は  project-advisor Subagent を使って特定する

## 2.1 バグ修正/新機能追加/リファクタリング

バグ修正/新機能追加/リファクタリングの場合は、既に`project/{feature}/plan/{feature}_plan.md`が存在するはずです。

与えられた要求をタスク化する場合、以下を必ず確認し、実行します

1. **要件定義書への反映確認** - その内容が要件定義書（`project/{feature}/spec/**/*.md`）に追記または修正されているか。不足・齟齬がある場合は追記、修正を行う。[MANDATORY]
2. **設計書への反映確認** - 設計変更を伴う場合、設計書（`project/{feature}/design/**/*.md`）に反映されているか。不足・齟齬がある場合は追記、修正を行う。 [MANDATORY]
3. **計画書にタスクを追加する** - 計画書にタスクを追加する場合は、「2.2 計画書を作成」を参考に行うこと [MANDATORY]

## 2.2 設計書作成とタスク追加のループ [MANDATORY]

### 開発の進め方

**重要**: 全ての要件を一度に設計するのではなく、以下のループで段階的に進めます：

```
1. 優先度の高い要件から設計書を1つ作成（DES-XXX）
   ↓
2. 人間のレビュー・承認を受ける
   ↓
3. 承認された設計書のタスクを計画書（{feature}_plan.md）に追加
   ↓
4. 次の要件の設計書作成に戻る（ステップ1へ）
```

このループを全ての要件がカバーされるまで繰り返します。

### なぜ段階的に進めるのか

- **レビューの質向上**: 1設計書ずつ丁寧にレビュー可能
- **早期実装開始**: 承認済み設計のタスクから順次実装開始可能
- **フィードバック反映**: 先行設計の知見を後続設計に活かせる
- **リスク低減**: 大規模な手戻りを防げる

## 2.3 計画書を作成・更新

- 作成するファイル名は `project/{feature}/plan/{feature}_plan.md`
- 新しい設計書が承認されるたびに、そのタスクを追加更新

### 計画書の詳細構成 [MANDATORY]

`docs/format/plan_format.md`に従い、以下のセクションで構成：

1. **要件トレーサビリティマトリクス**
```markdown
| ✓ | 要件ID | タイトル | 内容 | 設計ID |
|---|--------|---------|------|--------|
| ✅ | SCR-001 | 連絡先リスト画面 | メイン画面、グループサイドバー付き | DES-001, DES-002 |
| ☐ | FNC-001 | グループ管理 | グループの作成・編集・削除機能 | 設計書作成待ち |
```

2. **設計トレーサビリティマトリクス**
```markdown
| 設計ID | タイトル | 内容 | 要件ID | タスクID |
|--------|---------|------|--------|----------|
| DES-001 | 連絡先リスト設計 | 連絡先一覧表示とグループフィルタリング | SCR-001, CMP-001 | D-001～D-008, UI-001～UI-005 |
| DES-003 | グループ管理設計 | グループCRUD操作と連絡先移動 | FNC-001, FNC-002 | D-014～D-018, UI-012～UI-018 |
```

3. **タスク一覧（層ごとの表形式）**
```markdown
### Domain層タスク
| ✓ | 優先度 | タスクID | タイトル | やるべき内容 | 特筆事項 | 設計ID | 依存関係 | 必読 | 完了日 |
|---|-------|----------|---------|-------------|---------|--------|----------|------|--------|
| ☐ | 50 | D-001 | ContactService実装 | ・Actor-basedサービス実装<br>・連絡先CRUD操作<br>・権限管理機能 | - | DES-001 | - | contact_list_design | - |
```

4. **改定履歴**

### タスク作成の詳細手順 [MANDATORY]

#### 1. タスクの抽出方法
設計書から以下の順序でタスクを抽出：

1. **Entity/Enum定義タスク** - 設計書のDomain層セクションから抽出
2. **Protocol定義タスク** - DataStore/Repository Protocolの定義
3. **Service実装タスク** - ビジネスロジックの実装
4. **View/ViewModel実装タスク** - 設計書のUI層セクションから抽出
5. **Infrastructure実装タスク** - DataStore/Repository実装

#### 2. タスクID採番ルール
- **Domain層**: D-001, D-002, D-003...
- **UI層**: UI-001, UI-002, UI-003...
- **Infrastructure層**: I-001, I-002, I-003...
- **DI層**: DI-001, DI-002...
- **修正タスク**: FIX-001, FIX-002...

#### 3. 優先度設定基準
`docs/format/plan_format.md`のタスク分割表を参照：
- **90-99**: 緊急修正（バグ修正、パフォーマンス改善）
- **50-59**: Domain層（Entity、Service、Protocol）
- **30-39**: UI層（View、ViewModel、Component）
- **40-49**: Infrastructure層（DataStoreImpl、RepositoryImpl）
- **25-29**: DI層（Factory登録）

#### 4. task-executor実行を前提とした計画作成 [MANDATORY]
- **1タスク1Agent実行の原則**: 各タスクは1回のAgent実行で完結する単位
- **ビルド・テスト成功必須**: タスク完了時にビルド・テストが成功する規模
- **依存関係の明確化**: 先行タスクをタスクIDで明記
- **並列実行可能なタスク識別**: 依存関係がないタスクは並列実行可能

#### 実装順序の決定基準
1. **共通コンポーネント優先**: 複数画面で使用されるコンポーネントから実装
2. **依存関係考慮**: 依存される側から実装（MainTabView → 各Tab画面）
3. **機能の重要度**: コア機能の画面を優先
4. **開発効率**: 簡単な画面で実装パターンを確立してから複雑な画面へ

#### 依存関係マップの作成
```markdown
#### UIコンポーネント依存関係図
- 基本コンポーネント
  - Button系 (PrimaryButton, SecondaryButton)
  - Input系 (TextField, TextArea)
  - Display系 (Label, Badge)
- 中間コンポーネント
  - ListItem系 (ContactListItem, GroupListItem)
  - Card系 (InfoCard, DetailCard)
- 複合コンポーネント
  - List系 (ContactList, GroupList)
  - Form系 (ContactForm, SettingsForm)
```
※ 循環依存が発生しないよう確認すること

#### 確認 [MANDATORY]
- 計画書が、`docs/format/plan_format.md`のフォーマットに従っていることを確認
- **要件トレーサビリティマトリクスが以下を網羅していることを確認**：
  - `project/{feature}/spec/screens/**/*.md` の全画面要件（SCR-xxx）
  - `project/{feature}/spec/ui_components/**/*.md` の全UIコンポーネント要件（CMP-xxx）
  - `project/{feature}/spec/functions/**/*.md` の機能要件（FNC-xxx）
  - `project/{feature}/spec/business_logic/**/*.md` のビジネスロジック（BL-xxx）
  - `project/{feature}/spec/non_functional/**/*.md` の非機能要件（NF-xxx）
  - `project/{feature}/spec/data_models/**/*.md` のデータモデル（DM-xxx）
  - `project/{feature}/spec/external_interfaces/**/*.md` の外部インターフェース（EXT-xxx）
  - `project/{feature}/spec/navigation/**/*.md` のナビゲーション（NAV-xxx）
  - `project/{feature}/spec/theme/**/*.md` のデザイントークン・テーマ（THEME-xxx）
- **設計トレーサビリティマトリクスが以下を網羅していることを確認**：
  - 全設計書（DES-xxx）のエントリー
  - 各設計書の関連要件ID
  - 各設計書から生成されるタスクID
- **タスク一覧が層ごとの表形式で作成されていることを確認**
- **各タスクに以下が記載されていることを確認**：
  - タスクID（層略称-連番）
  - 優先度（1〜99）
  - やるべき内容（5〜10項目程度を目安）
  - 設計ID（関連する設計書）
  - 依存関係（先行タスクID）
- **タスクの完全性を確認**：
  - 全設計書がタスクに反映されているか
  - タスクの粒度が適切か（1Agent実行で完結）
  - 依存関係に循環がないか
- 計画書の承認を人間に依頼すること

### 2.4 AIレビュー実施 [MANDATORY]

計画書作成/更新時点で、人間レビュー依頼前に**Subagent**でレビューを実施：

**Subagent起動**:
```
subagent_type: general-purpose
prompt: |
  以下の計画書をレビューしてください。

  ## レビュー対象
  [作成した計画書のファイルパス]

  ## レビュー種別
  計画書

  ## 手順
  1. docs-advisor Subagentで関連ルール文書を特定・読み込み
  2. project-advisor Subagentで関連要件定義書・設計書を特定・読み込み
  3. docs/rules/base/review_criteria.md の「計画書レビュー観点」を参照
  4. レビュー実施（🔴致命的問題は0件になるまで修正）
  5. レビュー結果フォーマットで報告
```

**レビュー結果フォーマット**:
```markdown
## AIレビュー結果
- 🔴致命的: X件（修正済み: Y件）
- 🟡品質: X件
- 🟢改善: X件
```

### 2.5 project_toc.md更新について

**注意**: project_toc.mdは要件定義書・設計書のみが対象。
計画書（plan/）は `docs/format/project_toc_format.md` で除外されているため、**計画書作成時のproject_toc.md更新は不要**。

要件定義書・設計書を新規作成・更新した場合のみ、`project-toc-updater` Subagent を起動すること。
