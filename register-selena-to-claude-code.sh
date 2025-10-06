#!/bin/bash

# Swift SelenaをターゲットプロジェクトのClaude Codeに登録するスクリプト
# Usage: ./register-selena-to-claude-code.sh <target-project-directory>

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Swift Selena → Target Project 登録${NC}"
echo "=========================================="

# 引数チェック
if [ $# -ne 1 ]; then
    echo -e "${RED}エラー: ターゲットプロジェクトディレクトリを指定してください${NC}"
    echo ""
    echo "使い方:"
    echo "  $0 <target-project-directory>"
    echo ""
    echo "例:"
    echo "  $0 ~/projects/MyApp"
    exit 1
fi

# Swift-Selenaのパス（このスクリプトがあるディレクトリ）
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXECUTABLE_PATH="${SCRIPT_DIR}/.build/release/Swift-Selena"

# 実行ファイルの存在確認
if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo -e "${RED}エラー: Swift-Selena が見つかりません${NC}"
    echo "パス: $EXECUTABLE_PATH"
    echo ""
    echo "まず 'swift build -c release -Xswiftc -Osize' を実行してください"
    exit 1
fi

echo -e "${GREEN}✓${NC} 実行ファイルが見つかりました"
echo "  パス: $EXECUTABLE_PATH"

# ターゲットプロジェクト
TARGET_PROJECT="$1"

# ターゲットディレクトリの存在確認
if [ ! -d "$TARGET_PROJECT" ]; then
    echo -e "${RED}エラー: ターゲットディレクトリが見つかりません${NC}"
    echo "パス: $TARGET_PROJECT"
    exit 1
fi

TARGET_PROJECT_ABS="$( cd "$TARGET_PROJECT" && pwd )"
echo -e "${GREEN}✓${NC} ターゲットプロジェクト確認"
echo "  パス: $TARGET_PROJECT_ABS"

# ターゲットプロジェクトに移動してclaude mcp addを実行
echo ""
echo "Claude Code MCP設定に登録中..."

pushd "$TARGET_PROJECT_ABS" > /dev/null
claude mcp add swift-selena -- "$EXECUTABLE_PATH"
RESULT=$?
popd > /dev/null

if [ $RESULT -eq 0 ]; then
    echo ""
    echo -e "${GREEN}登録完了！${NC}"
    echo ""
    echo "ターゲットプロジェクト: $TARGET_PROJECT_ABS"
    echo ""
    echo "次のステップ:"
    echo "1. ターゲットプロジェクトでClaude Codeを開く (または再起動)"
    echo "   cd $TARGET_PROJECT_ABS"
    echo "2. Claude Codeでswift-selenaツールが利用可能になります"
    echo ""
    echo "使い方:"
    echo "  まず initialize_project ツールでプロジェクトを初期化してください"
else
    echo ""
    echo -e "${RED}登録に失敗しました${NC}"
    exit 1
fi
