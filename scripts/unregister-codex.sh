#!/bin/bash

# Swift Selena を Codex から登録解除するスクリプト
# Usage: ./scripts/unregister-codex.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Swift Selena → Codex 登録解除${NC}"
echo "================================"

if ! command -v codex &> /dev/null; then
    echo -e "${RED}エラー: codex コマンドが見つかりません${NC}"
    exit 1
fi

if codex mcp remove swift-selena 2>/dev/null; then
    echo -e "${GREEN}登録解除完了！${NC}"
    echo ""
    echo "Codex を再起動（IDE 拡張は Restart extension）してください。"
else
    echo -e "${YELLOW}swift-selena は登録されていませんでした${NC}"
fi
