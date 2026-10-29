#!/bin/bash
# release tag の整合性を検証する。
#
# 検証項目:
#   1. tag が存在する
#   2. tag が指す commit が main の「第1親ライン」上にある（main の本流に並ぶ）
#   3. tag が指す commit の Sources/Constants.swift の version == tag
#   4. Formula の tag: == tag
#   5. Formula に revision: が無い（revision は tag commit が Formula 自身を含むため
#      循環し、tag が main の本流上にあることと両立しない。tag: のみで解決する）
#
# 過去の brew install エラー（Issue #38）
#   「0.6.11 tag should be <X> but is actually <Y>」
# は revision と tag commit の不一致で起きた。revision を持たない運用にすることで
# 原理的に再発しない。
#
# Usage:
#   verify_release_tag.sh [version] [main_ref]
#     version 省略時は Sources/Constants.swift の canonical を使用
#     main_ref 省略時は origin/main（無ければ main）
#
# 全て満たす → exit 0 / 不整合 → 内容を stderr に出して exit 1
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

main_ref="${2:-}"
if [ -z "$main_ref" ]; then
  if git rev-parse --verify -q origin/main >/dev/null; then
    main_ref=origin/main
  else
    main_ref=main
  fi
fi

# 1. tag が指す commit
tag_commit=$(git rev-parse "${version}^{commit}" 2>/dev/null) || {
  echo "ERROR: tag '${version}' が見つかりません（tag 作成前か、push されていない可能性）" >&2
  exit 1
}
echo "tag ${version} が指す commit: $tag_commit"

errors=0

# 2. main の第1親ライン上にあるか
if git rev-list --first-parent "$main_ref" | grep -qx "$tag_commit"; then
  echo "ok    tag は ${main_ref} の第1親ライン上にある"
else
  echo "ERROR: tag commit '$tag_commit' が ${main_ref} の第1親ライン上にない（main の本流に打つこと）" >&2
  errors=$((errors + 1))
fi

# 3. tag commit 時点の Constants の version
const_ver=$(git show "${tag_commit}:Sources/Constants.swift" 2>/dev/null \
  | grep -E 'static let version = ' \
  | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/' | head -1)
if [ "$const_ver" != "$version" ]; then
  echo "ERROR: tag commit の Constants version='$const_ver' が tag '$version' と不一致" >&2
  errors=$((errors + 1))
else
  echo "ok    tag commit の Constants version: $const_ver"
fi

# 4 / 5. Formula（tag commit 時点のもの）
fml=$(git show "${tag_commit}:Formula/swift-selena.rb" 2>/dev/null)
fml_tag=$(printf '%s\n' "$fml" | grep -E '^\s*tag:' | sed -E 's/.*"([^"]+)".*/\1/' | head -1)
if [ "$fml_tag" != "$version" ]; then
  echo "ERROR: Formula tag='$fml_tag' が version '$version' と不一致" >&2
  errors=$((errors + 1))
else
  echo "ok    Formula tag: $fml_tag"
fi
if printf '%s\n' "$fml" | grep -qE '^\s*revision:'; then
  echo "ERROR: Formula に revision: が残っている（削除すること。tag: のみで解決する）" >&2
  errors=$((errors + 1))
else
  echo "ok    Formula に revision: が無い"
fi

if [ "$errors" -eq 0 ]; then
  echo ""
  echo "✓ tag ${version} (${tag_commit}) は整合している"
  exit 0
else
  echo "" >&2
  echo "✗ ${errors} 件の不整合" >&2
  exit 1
fi
