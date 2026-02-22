---
description: Pull Request作成
---

# Pull Request作成

現在のブランチからベースブランチへのPRを作成します。

## 前提条件

- `.github/PULL_REQUEST_TEMPLATE.md`があれば、このテンプレートに沿って作成すること [MANDATORY]
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
   - **重要**: `git status`（作業ツリーの状態）ではなく、`git log <base>..HEAD`（コミット差分）でPR作成可否を判断すること

2. **コミット差分確認** [MANDATORY]
   ```bash
   # ベースブランチとの差分コミット確認（必須）
   git log <base>..HEAD --oneline

   # コミットがない場合のみエラー
   # 「nothing to commit, working tree clean」は無関係（作業ツリーの状態）
   ```

3. **GitHub情報取得**
   - `git remote get-url origin`から自動抽出

4. **PR情報準備**
   - コミット履歴取得: `git log <base>..HEAD`
   - 変更ファイル統計: `git diff <base>...HEAD --stat`
   - gitリポジトリのオーナー・リポジトリ名抽出
   - ブランチ名からPRタイトル生成（feature/xxx → "[Feature] XXX"）

5. **PR作成**
   - リモートプッシュ（未プッシュの場合）
   - `gh pr create`でPR作成
   - ドラフトで作成
   - 不要な装飾削除:
      - 「🤖 Generated with [Claude Code](https://claude.com/claude-code)」
      - 「Co-Authored-By: Claude <noreply@anthropic.com>」

6. **完了処理**
   - PR URL表示
   - ブラウザで開くか確認

## 重要事項

- **オプション**: `--draft`, `--reviewer`, `--label`等は`gh pr create --help`参照

## サンドボックス対応 [MANDATORY]

サンドボックス環境では heredoc 用の一時ファイル作成が制限されるため、以下の形式で実行すること:

```bash
/bin/bash -c 'TMPDIR=/private/tmp/claude; gh pr create --draft --base main --title "タイトル" --body "$(cat <<EOF
PR本文をここに記述
EOF
)"'
```

**ポイント**:
- `/bin/bash -c '...'` でラップ
- `TMPDIR=/private/tmp/claude;` を先頭に設定
- heredoc の中身はシングルクォート内に記述



