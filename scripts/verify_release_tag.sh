#!/bin/bash
# release tag が指す commit と Formula の tag/revision が一致するか検証する。
#
# 今回（Issue #38 follow-up）の brew install エラー
#   「0.6.11 tag should be <X> but is actually <Y>」
# のように、git tag が指す commit と Formula の `revision` がズレると
# Homebrew が install を拒否する。これを release 時・tag push 時に機械検出する。
#
# verify_version_consistency.sh が「version 文字列の静的一致」を見るのに対し、
# 本スクリプトは「tag が指す commit SHA == Formula revision」という
# git object 識別子の一致を見る（tag 確定後にしか検証できない項目）。
#
# Usage:
#   verify_release_tag.sh [version]
#     version 省略時は Sources/Constants.swift の canonical を使用
#
# 全て一致 → exit 0 / 不一致 → 内容を stderr に出して exit 1
#
# 関連 Issue: #38（バージョン表記の統一）

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

version="${1:-}"
if [ -z "$version" ]; then
  version=$(grep -E 'static let version = ' Sources/Constants.swift \
    | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/' \
    | head -1)
fi
echo "version: $version"

# tag が指す commit
tag_commit=$(git rev-parse "${version}^{commit}" 2>/dev/null) || {
  echo "ERROR: tag '${version}' が見つかりません（tag 作成前か、push されていない可能性）" >&2
  exit 1
}
echo "tag ${version} が指す commit: $tag_commit"

# Formula の tag: と revision:
fml_tag=$(grep -E '^\s*tag:' Formula/swift-selena.rb \
  | sed -E 's/.*"([^"]+)".*/\1/' | head -1)
fml_rev=$(grep -E '^\s*revision:' Formula/swift-selena.rb \
  | sed -E 's/.*"([0-9a-f]+)".*/\1/' | head -1)

errors=0
if [ "$fml_tag" != "$version" ]; then
  echo "ERROR: Formula tag='$fml_tag' が version '$version' と不一致" >&2
  errors=$((errors + 1))
else
  echo "ok    Formula tag: $fml_tag"
fi
if [ "$fml_rev" != "$tag_commit" ]; then
  echo "ERROR: Formula revision='$fml_rev' が tag commit '$tag_commit' と不一致" >&2
  errors=$((errors + 1))
else
  echo "ok    Formula revision == tag が指す commit"
fi

if [ "$errors" -eq 0 ]; then
  echo ""
  echo "✓ Formula が tag ${version} (${tag_commit}) と整合している"
  exit 0
else
  echo "" >&2
  echo "✗ ${errors} 件の不整合。Formula の tag/revision を tag ${version} が指す commit (${tag_commit}) に合わせること" >&2
  exit 1
fi
