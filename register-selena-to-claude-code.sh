#!/bin/bash

# Swift Selena (RELEASE) をClaude Codeに登録するスクリプト
# 本番用
# Usage: ./register-selena-to-claude-code.sh <target-project-directory>

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 引数チェック
if [ $# -ne 1 ]; then
    echo -e "${RED}エラー: ターゲットプロジェクトディレクトリを指定してください${NC}"
    echo ""
    echo "使い方:"
    echo "  $0 <target-project-directory>"
    echo ""
    echo "例:"
    echo "  $0 /path/to/your/project"
    echo "  $0 ~/projects/MyApp"
    exit 1
fi

echo -e "${YELLOW}Swift Selena (RELEASE) → Claude Code 登録${NC}"
echo "=========================================="

# Swift-Selenaのパス（このスクリプトと同じディレクトリ）
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXECUTABLE_PATH="${SCRIPT_DIR}/.build/release/Swift-Selena"

# 実行ファイルの存在確認
if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo -e "${RED}エラー: Swift-Selena (release) が見つかりません${NC}"
    echo "パス: $EXECUTABLE_PATH"
    echo ""
    echo -e "${YELLOW}まず 'swift build -c release -Xswiftc -Osize' を実行してください${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} RELEASEビルドが見つかりました"
echo "  パス: $EXECUTABLE_PATH"

# バイナリのビルド日時を表示
BUILD_TIME=$(stat -f "%Sm" "$EXECUTABLE_PATH")
echo "  ビルド日時: $BUILD_TIME"

# ターゲットプロジェクト
TARGET_PROJECT="$1"
if [ ! -d "$TARGET_PROJECT" ]; then
    echo -e "${RED}エラー: ターゲットディレクトリが見つかりません${NC}"
    echo "パス: $TARGET_PROJECT"
    exit 1
fi

TARGET_PROJECT_ABS="$( cd "$TARGET_PROJECT" && pwd )"
echo ""
echo "登録先: $TARGET_PROJECT_ABS"

# ターゲットプロジェクトに移動して登録
echo ""
echo "Claude Code MCP設定に登録中..."

pushd "$TARGET_PROJECT_ABS" > /dev/null

# 既存の設定を削除（存在する場合）
claude mcp remove swift-selena 2>/dev/null || true

# 新しい設定を追加
claude mcp add swift-selena "$EXECUTABLE_PATH"
RESULT=$?

popd > /dev/null

if [ $RESULT -eq 0 ]; then
    echo ""
    echo -e "${GREEN}登録完了！${NC}"
    echo ""
    echo -e "${YELLOW}=== RELEASE版として登録されました ===${NC}"
    echo ""
    echo "次のステップ:"
    echo "1. 登録したプロジェクトでClaude Codeを再起動"
    echo "2. swift-selenaツールが利用可能になります"
else
    echo ""
    echo -e "${RED}登録に失敗しました${NC}"
    exit 1
fi
