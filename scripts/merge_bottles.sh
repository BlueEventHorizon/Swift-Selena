#!/bin/bash
# 目的: GitHub Release に添付された bottle JSON を Formula に反映する
# 使い方: scripts/merge_bottles.sh <version>   （例: scripts/merge_bottles.sh 0.6.11）
# 前提: bottle.yml の CI が完了し、Release に *.bottle.json が添付済みであること
#       作業ブランチ（develop から作成）上で実行し、変更された Formula を commit する
set -euo pipefail

VERSION="${1:?usage: $0 <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

gh release download "$VERSION" --pattern '*.bottle.json' --dir "$WORK" \
  --repo BlueEventHorizon/Swift-Selena

# brew bottle --merge は tap に登録された Formula を書き換える。
# tap が未登録ならこの作業ツリーを tap として登録する。
# すでに URL 形式で tap 済みの場合は Homebrew 側のクローンが書き換わるので、
# その差分をこの作業ツリーへ適用し、クローンは元に戻す。
brew tap blueeventhorizon/swift-selena "$ROOT" >/dev/null 2>&1 || true
TAP_DIR="$(brew --repo blueeventhorizon/swift-selena)"

brew bottle --merge --write --no-commit "$WORK"/*.bottle.json

if [ "$(cd "$TAP_DIR" && pwd -P)" != "$(cd "$ROOT" && pwd -P)" ]; then
  echo "tap は別クローン（$TAP_DIR）のため、差分を $ROOT に適用します"
  git -C "$TAP_DIR" diff -- Formula/swift-selena.rb | git -C "$ROOT" apply
  git -C "$TAP_DIR" checkout -- Formula/swift-selena.rb
fi

git -C "$ROOT" diff --stat Formula/swift-selena.rb
if git -C "$ROOT" diff --quiet -- Formula/swift-selena.rb; then
  echo "エラー: Formula に変更がありません（bottle が反映されていません）" >&2
  exit 1
fi
