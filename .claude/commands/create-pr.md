# Pull Request作成

現在のブランチからベースブランチへのPRを作成します。

## 前提条件

- `../.github/PULL_REQUEST_TEMPLATE.md`があれば、このテンプレートに沿って作成すること [CRITICAL]
- **gh CLI**: インストール・認証済み

## 使用方法

```
create-pr [ベースブランチ]
```

- **引数なし**: デフォルトブランチ自動判定（develop > main > master）
- **引数あり**: 指定ブランチへのPR作成

## 実行フロー

1. **事前確認**
   - gitリポジトリ・リモート設定確認
   - 現在ブランチがmain/masterでないこと確認
   - 未コミット変更の警告

2. **GitHub情報取得**
   - `project/info/github_info.md` が存在すれば情報取得する
   または
   - `git remote get-url origin`から自動抽出

3. **PR情報準備**
   - コミット履歴・変更ファイル取得（`git log`, `git diff`）
   - gitリポジトリのオーナー・リポジトリ
   - ブランチ名からPRタイトル生成（feature/xxx → "[Feature] XXX"）

4. **PR作成**
   - リモートプッシュ（未プッシュの場合）
   - `gh pr create`でPR作成
   - ドラフトで作成
   - 不要
      -「🤖 Generated with [Claude Code](https://claude.com/claude-code)"」
      - 「Co-Authored-By: Claude <noreply@anthropic.com>"  」
      とかはいらない

5. **完了処理**
   - PR URL表示
   - ブラウザで開くか確認

## 重要事項

- **オプション**: `--draft`, `--reviewer`, `--label`等は`gh pr create --help`参照



