#!/bin/bash

# Swift Selena (RELEASE) をClaude Codeから登録解除するスクリプト
# Usage: ./scripts/unregister-release.sh [target-project-directory]
#        引数なしの場合は現在のディレクトリから解除

set -e
# claude mcp remove の成否はエラーとして扱わないため、該当箇所で set +e を使用

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Swift Selena (RELEASE) → Claude Code 登録解除${NC}"
echo "=============================================="

# ターゲットプロジェクト（引数があればそれ、なければカレントディレクトリ）
if [ $# -ge 1 ] && [ -n "$1" ]; then
    # ~ を $HOME に展開
    TARGET_PROJECT="${1/#\~/$HOME}"
    if [ ! -d "$TARGET_PROJECT" ]; then
        echo -e "${RED}エラー: ディレクトリが見つかりません${NC}"
        echo "パス: $TARGET_PROJECT"
        exit 1
    fi
    TARGET_PROJECT_ABS="$( cd "$TARGET_PROJECT" && pwd )"
else
    TARGET_PROJECT_ABS="$( pwd )"
fi

echo "対象: $TARGET_PROJECT_ABS"
echo ""

# ターゲットプロジェクトに移動して解除
pushd "$TARGET_PROJECT_ABS" > /dev/null

set +e
claude mcp remove swift-selena 2>/dev/null
RESULT=$?
set -e

if [ $RESULT -eq 0 ]; then
    echo -e "${GREEN}登録解除完了！${NC}"
    echo ""
    echo "Claude Codeを再起動してください。"
else
    echo -e "${YELLOW}swift-selena は登録されていませんでした${NC}"
fi

popd > /dev/null
