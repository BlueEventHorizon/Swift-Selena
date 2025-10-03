# Pull Request作成

現在のブランチから指定したベースブランチへのPull Requestを作成します。

## 前提条件

- **docs/info/github_info.md** - GitHub情報（オーナー、リポジトリ、レビューア設定）
- **ghコマンド** - GitHub CLIがインストールされ、認証済みであること

を確認してください。

## 使用方法

```
create-pr [ベースブランチ]
```

- **引数あり**: 指定したブランチへのPRを作成
- **引数なし**: デフォルトブランチ（main/master/develop）へのPRを自動判定して作成
  - 優先順序 develop > main > master  （developがあれば、developへの merge PRとなる。なければ mainへのmerge PR）

## 実行フロー

### 1. 事前確認
1. **gitリポジトリの確認**
   - 現在のディレクトリがgitリポジトリであることを確認
   - リモートリポジトリが設定されていることを確認

2. **現在のブランチ確認**
   ```bash
   git branch --show-current
   ```
   - mainやmasterブランチでないことを確認（保護ブランチへの直接プッシュ防止）

3. **変更内容の確認**
   ```bash
   git status
   git diff --stat
   ```
   - コミットされていない変更がある場合は警告表示

4. **ベースブランチの決定**
   - 引数指定がある場合: その引数をベースブランチとして使用
   - 引数なしの場合: 
     1. リモートのデフォルトブランチを確認
     2. develop > main > master の優先順位で存在確認
     3. 見つかったブランチをベースブランチとして使用

### 2. PR情報の準備

1. **最近のコミット取得**
   ```bash
   git log <ベースブランチ>..HEAD --oneline
   ```

2. **変更ファイルリスト取得**
   ```bash
   git diff <ベースブランチ>...HEAD --name-status
   ```

3. **GitHub設定情報の取得**
   docs/info/github_info.mdから以下を自動取得：
   - オーナー名：リポジトリURL生成に使用
   - リポジトリ名：リポジトリURL生成に使用
   - レビューア：自動アサインに使用（設定されている場合）

4. **PR本文の自動生成**
   PRテンプレートファイルに基づいて以下を自動入力：
   
   - **概要**: 最近のコミットメッセージから自動生成
   - **やったこと**: 変更ファイルとコミットメッセージから要約
   - **レビュー観点**: 変更内容に応じた推奨レビューポイント
   - **レビューレベル**: 変更規模に応じて自動選択

### 3. PRタイトルの生成

ブランチ名とコミットメッセージから適切なタイトルを生成：
- feature/xxx → "[Feature] XXX"
- bugfix/xxx → "[Bugfix] XXX"
- refactor/xxx → "[Refactor] XXX"
- その他 → 最新のコミットメッセージを使用

### 4. 事前確認画面

```markdown
**Pull Request作成確認**

**現在のブランチ**: feature/example-branch
**ベースブランチ**: main
**タイトル**: [Feature] Example Branch Implementation

### PR本文プレビュー
---
[ここにPR本文のプレビューを表示]
---

### 変更内容サマリー
- コミット数: 5
- 変更ファイル数: 12
- 追加行数: +234
- 削除行数: -45

続行しますか？ (y/n/edit)
- y: このまま作成
- n: キャンセル
- edit: PR本文を編集
```

### 5. リモートへのプッシュ

PRを作成する前に、現在のブランチをリモートにプッシュ：

```bash
# アップストリームが設定されていない場合
git push -u origin <現在のブランチ名>

# すでに設定されている場合
git push
```

### 6. PR作成実行

```bash
gh pr create \
  --base <ベースブランチ> \
  --title "<PRタイトル>" \
  --body "<PR本文>" \
  [オプション]
```

オプション設定：
- `--draft`: ドラフトPRとして作成する場合
- `--assignee @me`: 自分をアサインする場合
- `--reviewer <reviewer>`: レビュアーを指定する場合
  - `docs/info/github_rule.md`のレビューア設定がある場合は自動適用
  - 手動指定で上書き可能
- `--label <label1>,<label2>`: ラベルを指定する場合
- `--milestone <milestone>`: マイルストーンを指定する場合

### 7. 作成後の処理

1. **PR URLの表示**
   ```
   ✅ Pull Request作成完了！
   URL: https://github.com/<オーナー>/<リポジトリ>/pull/123
   ```
   - URLのオーナー、リポジトリ部分はdocs/info/github_info.mdから自動取得

2. **ブラウザで開くか確認**
   ```
   ブラウザでPRを開きますか？ (y/n): 
   ```
   yの場合: `gh pr view --web`

3. **次のアクション提案**
   ```markdown
   ### 次のステップ
   1. PRの説明を追加で編集: gh pr edit 123
   2. レビューアーを追加: gh pr edit 123 --reviewer <レビューア>
      - `docs/info/github_rule.md`に設定されているレビューアが自動適用されていない場合のみ
   3. ラベルを追加: gh pr edit 123 --add-label bug,priority
   4. マイルストーンを設定: gh pr edit 123 --milestone "v1.0"
   ```

## カスタマイズ

### PRテンプレートの設定

GitHubのPRテンプレートは以下の場所に配置できます（優先度順）：

1. **`.github/PULL_REQUEST_TEMPLATE.md`** - 最も一般的な場所
2. **`.github/pull_request_template.md`** - 小文字バージョン  
3. **`.github/PULL_REQUEST_TEMPLATE/`** - 複数テンプレート用ディレクトリ
   - `bug-fix.md`, `feature.md`, `refactor.md` など用途別テンプレート

**テンプレートの自動適用：**
- 上記ファイルが存在する場合、PR作成時に自動的に内容が適用されます
- 複数テンプレートがある場合は、ユーザーが選択できます
- テンプレートがない場合は、デフォルトの構造で本文を生成します

**テンプレート使用例：**
```bash
# 特定のテンプレートを指定してPR作成
gh pr create --template feature

# 複数テンプレートがある場合の選択
gh pr create
# → テンプレート選択画面が表示される
```

**カスタマイズ方法：**
プロジェクト固有のPRテンプレートがある場合は、それに合わせて自動生成ロジックを調整します。

## トラブルシューティング

### よくあるエラーと対処法

1. **認証エラー**
   ```
   エラー: GitHub CLIの認証が必要です
   対処: gh auth login を実行してください
   ```

2. **リモートが見つからない**
   ```
   エラー: リモートリポジトリが設定されていません
   対処: git remote add origin <URL> を実行してください
   ```

3. **ブランチが最新でない**
   ```
   警告: ベースブランチより古い可能性があります
   推奨: git pull origin <ベースブランチ> でマージしてください
   ```

4. **コンフリクトの可能性**
   ```
   警告: コンフリクトの可能性があります
   ファイル: [コンフリクトしそうなファイルリスト]
   ```

## 高度な使用例

### 特定のコミット範囲でPR作成
```
create-pr main --commits HEAD~3..HEAD
```

### ドラフトPRとして作成
```
create-pr --draft
```

### レビュアーとラベルを指定
```
create-pr main --reviewer user1,user2 --label bug,urgent
```

### github_rule.mdのレビューア設定を使用
```
create-pr main
```
※ `docs/info/github_rule.md`にレビューアが設定されている場合、自動で適用されます
