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

# ローカルの作業ツリーを tap として使い、Formula を直接書き換える
brew tap blueeventhorizon/swift-selena "$ROOT" >/dev/null 2>&1 || true
brew bottle --merge --write --no-commit "$WORK"/*.bottle.json

git -C "$ROOT" diff --stat Formula/swift-selena.rb
