#!/bin/bash

# Swift Selena MCP Server を Cursor から登録解除するスクリプト
# Usage: ./scripts/unregister-cursor.sh [target-project-directory]
#        引数なし: 全プロジェクト共通の ~/.cursor/mcp.json から解除
#        引数あり: 対象プロジェクトの .cursor/mcp.json から解除

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Swift Selena → Cursor 登録解除${NC}"
echo "================================="

# 解除対象の設定ファイル（register-cursor.sh と同じ規則）
if [ $# -ge 1 ] && [ -n "$1" ]; then
    TARGET_PROJECT="${1/#\~/$HOME}"
    if [ ! -d "$TARGET_PROJECT" ]; then
        echo -e "${RED}エラー: ターゲットディレクトリが見つかりません${NC}"
        echo "パス: $TARGET_PROJECT"
        exit 1
    fi
    CONFIG_FILE="$( cd "$TARGET_PROJECT" && pwd )/.cursor/mcp.json"
else
    CONFIG_FILE="$HOME/.cursor/mcp.json"
fi

echo "対象: $CONFIG_FILE"
echo ""

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}設定ファイルが見つかりません${NC}"
    echo "swift-selena は登録されていませんでした。"
    exit 0
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}エラー: jq がインストールされていません${NC}"
    echo "インストール: brew install jq"
    echo ""
    echo "手動で設定ファイルを編集し、mcpServers から swift-selena エントリを削除してください："
    echo "  $CONFIG_FILE"
    exit 1
fi

if ! jq -e '.mcpServers."swift-selena"' "$CONFIG_FILE" > /dev/null 2>&1; then
    echo -e "${YELLOW}swift-selena は登録されていませんでした${NC}"
    exit 0
fi

# バックアップを残してから swift-selena を削除
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
echo -e "${GREEN}✓${NC} バックアップ作成: ${CONFIG_FILE}.backup"
jq 'del(.mcpServers."swift-selena")' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

echo -e "${GREEN}登録解除完了！${NC}"
echo ""
echo "Cursor を再起動してください。"
