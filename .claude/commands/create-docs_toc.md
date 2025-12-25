# AI検索用の文書検索インデックスを生成する

docs_tocは**AIがタスク実行時に必要な文書を特定するためのインデックス**として設計する。

---

## 重要な設計原則 [CRITICAL]

### AIの実際の行動パターン
- タスクを与えられる → 必要な文書を読む → 実装する
- 「キーワードで検索」はしない
- 「このタスクで何を読むべきか」が重要

### タスクの粒度
- main_plan.mdのタスク粒度に合わせる
- 例：「ContactService実装」「ContactListView実装」
- 「ViewStateパターンを使う」のような細分化は不要（View/ViewModel実装の中で使うテクニック）

### 不要なもの
- キーワードインデックス（AIはキーワードで検索しない）
- タグ別インデックス（同上）
- 文書間の関係性マップ（タスク別リファレンスで十分）
- 各文書の「主なトピック」詳細（文書を読めば分かる）

---

## 引数

```
create-docs_toc -target <対象ディレクトリ>
```

### パラメータ

| パラメータ | 必須 | 説明 | デフォルト値 | 例 |
|----------|------|------|------------|-----|
| `-target` | 必須 | ToC生成対象のディレクトリ | なし | `-target docs/` |

### 使用例

```bash
# 基本的な使い方
create-docs_toc -target docs/
```

---

## 成果物

- **ファイル名**: `<target_dir>/docs_toc.md`
- **例**: `docs/docs_toc.md`

---

## 出力構造

### 必須セクション構成

```markdown
# 開発文書検索インデックス

---
name: 開発文書検索インデックス
description: {この文書の目的を1行で}
---

## Critical Requirements（必読文書）

**全タスクで必ず参照すること** [CRITICAL]

| 文書 | 目的 |
|-----|------|
| `rules/project_rule.md` | プロジェクト開始時・タスク開始前に基本ルールを確認する |
| `rules/common/architecture_rule.md` | アーキテクチャ設計・実装前にレイヤー構成を確認する |
| `rules/common/coding_rule.md` | コード記述前に規約を確認する |

---

## 状況別ガイド

### 開発開始時
1. `rules/project_rule.md`
2. 本ファイル（docs_toc.md）を通読
3. `project/project_toc.md`（存在する場合）

### タスク実行時（Claude）
1. `workflow/dev/task_orchestration_guide.md`

### タスク実行時（Agent）
1. `workflow/dev/task_execution_workflow.md`

---

## タスク別リファレンス

**Critical Requirementsに加えて、以下を参照**

### Domain層

#### Serviceを実装する
1. `rules/domain/domain_core.md`
2. `rules/domain/unit_test.md`
3. `rules/domain/domain_factory.md`

#### Entity/Enumを定義する
1. `rules/domain/domain_core.md`

#### DataStore Protocolを実装する
1. `rules/domain/domain_protocol_mock.md`
2. `rules/domain/stream_manager_usage.md`

#### Repository Protocolを実装する
1. `rules/domain/domain_protocol_mock.md`

#### Mockを実装する
1. `rules/domain/domain_protocol_mock.md`
2. `rules/domain/domain_factory.md`

#### Unit Testを書く（TDD）
1. `rules/domain/unit_test.md`
2. `rules/domain/domain_protocol_mock.md`

### UI層

#### View/ViewModelを実装する
1. `rules/ui/ui_core.md`
2. `rules/ui/design_token.md`

#### UIComponent/ViewModifierを作成する
1. `rules/ui/ui_components.md`
2. `rules/ui/design_token.md`

#### デザイントークンを設定する
1. `rules/ui/design_token.md`

### Infrastructure層

#### DataStore実装を作成する
1. `rules/infrastructure/stream_manager_best_practices.md`
2. `rules/domain/stream_manager_usage.md`

#### Repository実装を作成する
1. `rules/common/architecture_rule.md`

### DI層

#### Resolverを実装する
1. `rules/di/di.md`
2. `rules/domain/domain_factory.md`

### ワークフロー

#### 要件定義書を作成する（既存アプリから）
1. `templates/spec_format.md`
2. `workflow/plan/import_app_workflow.md`

#### 要件定義書を作成する（Figmaから）
1. `templates/spec_format.md`
2. `workflow/plan/import_figma_workflow.md`

#### 設計書を作成する
1. `templates/design_format.md`
2. `workflow/plan/design_workflow.md`

#### 計画書を作成する
1. `templates/plan_format.md`
2. `workflow/plan/planning_workflow.md`

#### タスクを実行する（Claude）
1. `workflow/dev/task_orchestration_guide.md`

#### タスクを実行する（Agent）
1. `workflow/dev/task_execution_workflow.md`

#### コードをライブラリ化する
1. `workflow/refactoring/library_creator_workflow.md`

#### Code Headerを追加する
1. `templates/code_header_format.md`

### 原則・禁止事項を確認する

#### 開発原則を確認する
1. `rules/common/principles_of_software_development.md`

#### やってはいけないことを確認する
1. `rules/common/bad_practices.md`
2. `rules/ui/bad_practices_ui.md`

#### MCP活用方法を確認する
1. `rules/common/develop_with_agent_rule.md`

---

## 全文書一覧

### rules/（開発ルール）

| ファイル | 目的 |
|---------|------|
| `project_rule.md` | プロジェクト開始時にAI対話・開発の基本ルールを確認する |
| `common/architecture_rule.md` | 5層Clean Architectureの構成・依存関係を理解する |
...（対象ディレクトリの全ファイルを列挙）

### workflow/（ワークフロー）

| ファイル | 目的 |
|---------|------|
...（対象ディレクトリの全ファイルを列挙）

### templates/（文書テンプレート）

| ファイル | 目的 |
|---------|------|
...（対象ディレクトリの全ファイルを列挙）
```

---

## 実装手順

### Phase 1: ファイル収集

1. **対象ファイルの取得**
   ```
   Glob("{target}/**/*.md") で全マークダウンファイルを取得
   ```

2. **ファイルリストの作成**
   ```
   処理対象のファイルパスリストを作成
   ディレクトリ構造順にソート
   ```

### Phase 2: ファイル分析

各ファイルについて以下を実行：

1. **基本情報の抽出**
   - `Read()` でファイル内容を読み込み
   - H1タイトル（`# タイトル名`）を抽出
   - 冒頭の概要から「目的」を1行で要約

### Phase 3: ToC構造の作成

1. **Critical Requirements**: 最重要の3文書を固定で記載
2. **状況別ガイド**: 固定構造で記載
3. **タスク別リファレンス**: main_plan.mdのタスク粒度に合わせて構築
4. **全文書一覧**: ディレクトリ別の表形式で列挙

### Phase 4: ファイル出力

1. **Markdown版の出力**
   - `Write()` で `{target}/docs_toc.md` に保存

2. **完了報告**
   ```
   ToC生成完了
   - 対象: {target}
   - 処理ファイル数: N件
   - 出力: docs_toc.md
   ```

---

## 注意事項

### 必ず守るべき原則

1. **タスク粒度の維持**
   - main_plan.mdのタスク粒度に合わせる
   - 「Serviceを実装する」「View/ViewModelを実装する」など
   - 細分化しすぎない（ViewStateパターン、SharedDataパターン等は独立タスクにしない）

2. **シンプルさの維持**
   - キーワードインデックスは作成しない
   - タグ別インデックスは作成しない
   - 文書間の関係性マップは作成しない
   - 「主なトピック」詳細は記載しない

3. **相対パスを使用**
   - 絶対パスは使用しない
   - target ディレクトリからの相対パス

4. **日本語で記述**
   - タイトル・説明は日本語
   - ファイルパスは変更しない

### 既存ToC更新時の考慮事項

- 既存の構造を尊重する
- 大幅な変更は避ける
- 段階的な改善を推奨

---

## 生成AIへの実行例

```
コマンド: /create-docs_toc -target docs/

期待される動作:
1. docs/ 配下の全.mdファイルを取得
2. 各ファイルを分析
3. Critical Requirements + 状況別ガイド + タスク別リファレンス + 全文書一覧 の構造で作成
4. docs/docs_toc.md に出力
5. 完了報告
```
