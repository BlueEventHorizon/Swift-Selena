#!/bin/bash

# Swift Selena MCP Server を Claude Desktop から登録解除するスクリプト

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Swift Selena → Claude Desktop 登録解除${NC}"
echo "======================================="

CONFIG_FILE="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}設定ファイルが見つかりません: $CONFIG_FILE${NC}"
    echo "swift-selena は登録されていませんでした。"
    exit 0
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}エラー: jq がインストールされていません${NC}"
    echo "インストール: brew install jq"
    echo ""
    echo "手動で設定ファイルを編集してください："
    echo "  nano \"$CONFIG_FILE\""
    echo ""
    echo "mcpServers から swift-selena エントリを削除してください。"
    exit 1
fi

# バックアップ作成
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
echo -e "${GREEN}✓${NC} バックアップ作成: ${CONFIG_FILE}.backup"

# swift-selena を削除
jq 'del(.mcpServers."swift-selena")' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

echo -e "${GREEN}登録解除完了！${NC}"
echo ""
echo "Claude Desktop を再起動してください。"
