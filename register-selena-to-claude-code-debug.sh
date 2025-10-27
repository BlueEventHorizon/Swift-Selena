#!/bin/bash

# Swift Selena (DEBUG) をClaude Codeに登録するスクリプト
# 開発・テスト用
# Usage: ./register-selena-to-claude-code-debug.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}Swift Selena (DEBUG) → Claude Code 登録${NC}"
echo "=========================================="

# Swift-Selenaのパス（このスクリプトがあるディレクトリ）
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXECUTABLE_PATH="${SCRIPT_DIR}/.build/arm64-apple-macosx/debug/Swift-Selena"

# クリーンビルドを実行
echo ""
echo -e "${CYAN}クリーンビルド実行中...${NC}"
cd "$SCRIPT_DIR"
swift package clean
swift build
BUILD_RESULT=$?

if [ $BUILD_RESULT -ne 0 ]; then
    echo -e "${RED}ビルドに失敗しました${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} DEBUGビルド完了"

# 実行ファイルの存在確認
if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo -e "${RED}エラー: Swift-Selena (debug) が見つかりません${NC}"
    echo "パス: $EXECUTABLE_PATH"
    exit 1
fi

echo -e "${GREEN}✓${NC} 実行ファイル確認"
echo "  パス: $EXECUTABLE_PATH"

# バイナリのビルド日時を表示
BUILD_TIME=$(stat -f "%Sm" "$EXECUTABLE_PATH")
echo "  ビルド日時: $BUILD_TIME"

# Swift-Selenaプロジェクト自体に登録
echo ""
echo -e "${CYAN}Claude Code MCP設定に登録中...${NC}"

# 既存の設定を削除（存在する場合）
claude mcp remove swift-selena 2>/dev/null || true

# 新しい設定を追加
claude mcp add swift-selena -- "$EXECUTABLE_PATH"
RESULT=$?

if [ $RESULT -eq 0 ]; then
    echo ""
    echo -e "${GREEN}登録完了！${NC}"
    echo ""
    echo -e "${CYAN}=== DEBUG版として登録されました ===${NC}"
    echo "登録先: Swift-Selenaプロジェクト"
    echo ""
    echo "次のステップ:"
    echo "1. Swift-SelenaプロジェクトでClaude Codeを再起動"
    echo "   (Claude Codeを終了して再起動)"
    echo ""
    echo "2. swift-selenaツールが利用可能になります"
    echo "   例: 他のプロジェクトを解析する場合"
    echo "   initialize_project(project_path: \"/path/to/ContactB\")"
    echo "   search_files_without_pattern(pattern: \"^import\")"
    echo ""
    echo -e "${YELLOW}注意: DEBUGビルドのため、リリース版より遅い可能性があります${NC}"
else
    echo ""
    echo -e "${RED}登録に失敗しました${NC}"
    exit 1
fi
