#!/bin/bash

# Swift Selena (RELEASE) をClaude Codeに登録するスクリプト
# 本番用
# Usage: ./scripts/register-release.sh [target-project-directory]
#        引数なし: 全プロジェクト共通（user スコープ、claude mcp add -s user）に登録
#        引数あり: 対象プロジェクトのみ（local スコープ）に登録

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Swift Selena (RELEASE) → Claude Code 登録${NC}"
echo "=========================================="

# Swift-Selenaのパス（このスクリプトの1階層上がプロジェクトルート）
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
EXECUTABLE_PATH="${PROJECT_ROOT}/.build/release/Swift-Selena"

# 実行ファイルの存在確認
if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo -e "${RED}エラー: Swift-Selena (release) が見つかりません${NC}"
    echo "パス: $EXECUTABLE_PATH"
    echo ""
    echo -e "${YELLOW}まず 'make build-release' を実行してください${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} RELEASEビルドが見つかりました"
echo "  パス: $EXECUTABLE_PATH"

# バイナリのビルド日時を表示
BUILD_TIME=$(stat -f "%Sm" "$EXECUTABLE_PATH")
echo "  ビルド日時: $BUILD_TIME"

# 登録スコープ（引数があれば対象プロジェクトの local、なければ全プロジェクト共通の user）
if [ $# -ge 1 ] && [ -n "$1" ]; then
    # ~ を $HOME に展開
    TARGET_PROJECT="${1/#\~/$HOME}"
    if [ ! -d "$TARGET_PROJECT" ]; then
        echo -e "${RED}エラー: ターゲットディレクトリが見つかりません${NC}"
        echo "パス: $TARGET_PROJECT"
        exit 1
    fi
    TARGET_PROJECT_ABS="$( cd "$TARGET_PROJECT" && pwd )"
    echo ""
    echo "登録先: $TARGET_PROJECT_ABS（local スコープ）"
    echo ""
    echo "Claude Code MCP設定に登録中..."

    # ターゲットプロジェクトに移動して登録（既存の設定は削除してから追加）
    pushd "$TARGET_PROJECT_ABS" > /dev/null
    claude mcp remove -s local swift-selena 2>/dev/null || true
    set +e
    claude mcp add swift-selena -- "$EXECUTABLE_PATH"
    RESULT=$?
    set -e
    popd > /dev/null
else
    echo ""
    echo "登録先: 全プロジェクト共通（user スコープ）"
    echo ""
    echo "Claude Code MCP設定に登録中..."

    # 既存の user スコープ設定は削除してから追加
    claude mcp remove -s user swift-selena 2>/dev/null || true
    set +e
    claude mcp add -s user swift-selena -- "$EXECUTABLE_PATH"
    RESULT=$?
    set -e
fi

if [ $RESULT -eq 0 ]; then
    echo ""
    echo -e "${GREEN}登録完了！${NC}"
    echo ""
    echo -e "${YELLOW}=== RELEASE版として登録されました ===${NC}"
    echo ""
    echo "次のステップ:"
    echo "1. Claude Codeを再起動（local スコープの場合は登録したプロジェクトで）"
    echo "2. swift-selenaツールが利用可能になります"
else
    echo ""
    echo -e "${RED}登録に失敗しました${NC}"
    exit 1
fi
