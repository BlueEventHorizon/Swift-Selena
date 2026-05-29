#!/bin/bash
# プロジェクト内のバージョン表記が整合していることを検証する。
#
# canonical: Sources/Constants.swift の `static let version = "X.Y.Z"` 行
# 比較対象:
#   - .version-config.yaml の tag_format が "{version}"
#   - Formula/swift-selena.rb の tag: "X.Y.Z" が canonical と一致
#   - CHANGELOG.md の最新「v なし」entry (`## VERSION - DATE`) の VERSION 部分が canonical と一致
#
# 全て一致 → exit 0
# いずれか不一致 → 検出内容を stderr に列挙して exit 1
#
# 関連 Issue: #38 (バージョン表記の統一)

set -uo pipefail

# スクリプトはリポジトリ root から実行される想定
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

# canonical を抽出
canonical=$(grep -E 'static let version = ' Sources/Constants.swift \
  | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/' \
  | head -1)
if [ -z "$canonical" ]; then
  echo "ERROR: canonical version not found in Sources/Constants.swift" >&2
  exit 1
fi
echo "canonical (Sources/Constants.swift): $canonical"

errors=0

# .version-config.yaml の tag_format
tag_format=$(grep -E '^\s*tag_format:' .version-config.yaml \
  | sed -E 's/.*tag_format:[[:space:]]*"?([^"#]+)"?.*/\1/' \
  | head -1 \
  | sed -E 's/[[:space:]]+$//')
if [ "$tag_format" != "{version}" ]; then
  echo "ERROR: .version-config.yaml tag_format must be \"{version}\" (v なし), got: '$tag_format'" >&2
  errors=$((errors + 1))
else
  echo "ok    .version-config.yaml tag_format: \"{version}\""
fi

# Formula/swift-selena.rb の tag
if [ -f Formula/swift-selena.rb ]; then
  formula_tag=$(grep -E '^\s*tag:[[:space:]]+"' Formula/swift-selena.rb \
    | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/' \
    | head -1)
  if [ "$formula_tag" != "$canonical" ]; then
    echo "ERROR: Formula/swift-selena.rb tag is '$formula_tag', expected '$canonical' (canonical)" >&2
    errors=$((errors + 1))
  else
    echo "ok    Formula/swift-selena.rb tag: \"$formula_tag\""
  fi
else
  echo "warn  Formula/swift-selena.rb not present (skipping)"
fi

# CHANGELOG.md の最新「v なし」entry
# 過去の `## v0.6.X` 表記は historical record として skip し、`## X.Y.Z` 形式の最初のヒットを取る
changelog_latest=$(grep -E '^## [0-9]+\.[0-9]+\.[0-9]+([[:space:]]|$)' CHANGELOG.md \
  | head -1 \
  | sed -E 's/^## ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
if [ -z "$changelog_latest" ]; then
  echo "ERROR: No new-format (v なし) CHANGELOG entry found in CHANGELOG.md" >&2
  errors=$((errors + 1))
elif [ "$changelog_latest" != "$canonical" ]; then
  echo "ERROR: CHANGELOG.md latest non-v entry is '$changelog_latest', expected '$canonical' (canonical)" >&2
  errors=$((errors + 1))
else
  echo "ok    CHANGELOG.md latest non-v entry: $changelog_latest"
fi

if [ "$errors" -eq 0 ]; then
  echo ""
  echo "✓ All sources are consistent with canonical version $canonical"
  exit 0
else
  echo "" >&2
  echo "✗ $errors drift(s) detected" >&2
  exit 1
fi
