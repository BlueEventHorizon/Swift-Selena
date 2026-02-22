# レビュー実行コマンド

## 使用方法

```
/review <種別> [対象]
```

### 種別（必須）
- `spec` - 要件定義書レビュー
- `design` - 設計書レビュー
- `code` - コードレビュー

### 対象（任意）
- **ファイルパス**: `project/csv_import/spec/screens/SCR-001_xxx.md`
- **Feature名**: `csv_import`（`project/csv_import/` 配下全体）
- **ディレクトリ**: `App/View/`（code時のみ）
- **省略時**: 現在のブランチの変更差分

### 使用例

```bash
# 要件定義書レビュー
/review spec project/csv_import/spec/screens/SCR-001_import_screen_spec.md
/review spec csv_import                    # Feature全体のspec
/review spec                               # ブランチ差分のspec

# 設計書レビュー
/review design project/csv_import/design/DES-025_csv_import_design.md
/review design csv_import                  # Feature全体のdesign
/review design                             # ブランチ差分のdesign

# コードレビュー
/review code App/View/CSVImport/
/review code csv_import                    # Feature関連コード
/review code                               # ブランチ差分のコード
```

---

## 引数の解析: $ARGUMENTS

**入力**: `$ARGUMENTS`

1. 最初の単語を「種別」として取得: `spec` | `design` | `code`
2. 残りを「対象」として取得

**種別が不明な場合**: ユーザーに確認を求める

---

## 共通: Subagentでレビュー実行 [MANDATORY]

**全てのレビューはSubagentで実行**（クリーンなコンテキストで客観的レビュー）

```
subagent_type: general-purpose
prompt: |
  以下の[種別]をレビューしてください。

  ## レビュー対象
  [対象ファイルパス/Feature名]

  ## レビュー種別
  [要件定義書 / 設計書 / コード]

  ## 手順
  1. docs-advisor Subagentで関連ルール文書を特定・読み込み
  2. project-advisor Subagentで関連要件定義書・設計書を特定・読み込み
  3. docs/rules/base/review_criteria.md の該当セクションを参照
  4. レビュー実施
  5. 🔴致命的問題は修正提案を含めて報告
  6. レビュー結果フォーマットで報告
```

---

## 種別ごとの詳細

### spec - 要件定義書レビュー

**対象**: `project/{feature}/spec/**/*.md`

**レビュー観点**（`docs/rules/base/review_criteria.md` 参照）:
- 🔴致命的: What/Howの混同、曖昧表現、要件漏れ、矛盾
- 🟡品質: 要件ID不整合、相互参照エラー、フォーマット違反、用語不統一
- 🟢改善: 表現の明確化、図表追加、構成改善

**Subagentプロンプト**:
```
subagent_type: general-purpose
prompt: |
  以下の要件定義書をレビューしてください。

  ## レビュー対象
  [対象]

  ## レビュー種別
  要件定義書

  ## 手順
  1. docs-advisor Subagentで spec_format.md, coding_rule.md を取得
  2. project-advisor Subagentで関連する他の要件定義書を取得
  3. docs/rules/base/review_criteria.md の「要件定義書レビュー観点」を参照
  4. レビュー実施（🔴致命的問題は0件になるまで修正提案）
  5. レビュー結果フォーマットで報告
```

---

### design - 設計書レビュー

**対象**: `project/{feature}/design/**/*.md`

**レビュー観点**（`docs/rules/base/review_criteria.md` 参照）:
- 🔴致命的: アーキテクチャルール違反、要件未反映、Entity必須Protocol欠落、Service設計違反
- 🟡品質: DataStore設計不備、データフロー不整合、DI設計欠落、ViewModel設計不備
- 🟢改善: 既存資産活用、パターン統一、拡張性考慮

**Subagentプロンプト**:
```
subagent_type: general-purpose
prompt: |
  以下の設計書をレビューしてください。

  ## レビュー対象
  [対象]

  ## レビュー種別
  設計書

  ## 手順
  1. docs-advisor Subagentで design_format.md, coding_rule.md を取得
  2. project-advisor Subagentで関連要件定義書・既存設計書を取得
  3. docs/rules/base/review_criteria.md の「設計書レビュー観点」を参照
  4. レビュー実施（🔴致命的問題は0件になるまで修正提案）
  5. レビュー結果フォーマットで報告
```

---

### code - コードレビュー

**対象**: `Sources/`（Selena/, Tools/, Logging/）

**レビュー観点**（`docs/rules/base/review_criteria.md` 参照）:
- 🔴致命的: コンパイルエラー、実行時例外、セキュリティ脆弱性、アーキテクチャ違反
- 🟡品質: 保守困難、拡張困難、テスト困難、ルール違反
- 🟢改善: 最適化可能、慣用法違反、文書化不足

**対象の決定**:
1. ファイル/ディレクトリ指定: その範囲
2. Feature指定: 関連するコード（Sources/配下）
3. 省略時: `git diff develop...HEAD` の差分

**Subagentプロンプト**:
```
subagent_type: general-purpose
prompt: |
  以下のコードをレビューしてください。

  ## レビュー対象
  [対象]

  ## レビュー種別
  コード

  ## 手順
  1. docs-advisor Subagentで coding_rule.md を取得
  2. project-advisor Subagentで関連要件定義書・設計書を取得
  3. docs/rules/base/review_criteria.md の「コードレビュー観点」を参照
  4. レビュー実施（🔴致命的問題は0件になるまで修正提案）
  5. レビュー結果フォーマットで報告
```

---

## レビュー結果フォーマット [MANDATORY]

```markdown
## AIレビュー結果

### 🔴致命的問題
1. **[問題名]**: [具体的な説明]
   - 箇所: [ファイル名:行番号 / セクション名]
   - 参照: [関連ルール/要件定義書]
   - 修正案: [具体的な修正提案]

### 🟡品質問題
1. **[問題名]**: [具体的な説明]
   - 箇所: [ファイル名:行番号 / セクション名]

### 🟢改善提案
1. **[提案名]**: [具体的な説明]

### サマリー
- 🔴致命的: X件
- 🟡品質: X件
- 🟢改善: X件

### 修正の提案

🔴致命的問題がある場合、以下の選択肢を提示:
1. **全自動修正**: 「全て直して」で🔴問題を優先修正
2. **個別修正**: 「[問題名]を直して」で特定問題のみ修正
3. **手動修正**: レビュー結果を参考に自分で修正
```

---

## 問題数制限 [MANDATORY]

| カテゴリ | 上限 | 超過時の対応 |
|---------|------|-------------|
| 🔴致命的 | 10件 | 超過分は次回レビューへ |
| 🟡品質 | 10件 | 超過分は次回レビューへ |
| 🟢改善 | 5件 | 超過分は省略 |
