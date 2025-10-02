#!/bin/bash

# Swift Selena MCP ServerをClaude Code（claude CLI）に登録するスクリプト

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Swift Selena MCP Server → Claude Code 登録${NC}"
echo "=========================================="

# 現在のディレクトリを取得
CURRENT_DIR="$(pwd)"
EXECUTABLE_PATH="${CURRENT_DIR}/.build/debug/SwiftMCPServer"

# 実行ファイルの存在確認
if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo -e "${RED}エラー: SwiftMCPServer が見つかりません${NC}"
    echo "パス: $EXECUTABLE_PATH"
    echo ""
    echo "まず 'swift build' を実行してください"
    exit 1
fi

echo -e "${GREEN}✓${NC} 実行ファイルが見つかりました"
echo "  パス: $EXECUTABLE_PATH"

# claude CLIがインストールされているか確認
if ! command -v claude &> /dev/null; then
    echo -e "${RED}エラー: claude CLI が見つかりません${NC}"
    echo ""
    echo "Claude Codeをインストールしてください："
    echo "  https://docs.anthropic.com/claude/docs/claude-code"
    exit 1
fi

echo -e "${GREEN}✓${NC} claude CLI が見つかりました"

# 既存の登録を確認
echo ""
echo "既存のMCPサーバーを確認中..."
if claude mcp list 2>/dev/null | grep -q "swift-selena"; then
    echo -e "${YELLOW}警告: swift-selena は既に登録されています${NC}"
    read -p "上書きしますか？ (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "キャンセルしました"
        exit 0
    fi
    claude mcp remove swift-selena 2>/dev/null || true
fi

# Claude Codeに登録
echo ""
echo "Claude Codeに登録中..."
claude mcp add swift-selena -- "$EXECUTABLE_PATH"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}登録完了！${NC}"
    echo ""
    echo "次のステップ:"
    echo "1. Claude Codeでプロジェクトを開く"
    echo "2. 以下のコマンドでMCPサーバーを確認:"
    echo "   claude mcp list"
    echo ""
    echo "使い方:"
    echo "  まず initialize_project ツールでプロジェクトを初期化してください"
else
    echo ""
    echo -e "${RED}登録に失敗しました${NC}"
    exit 1
fi
