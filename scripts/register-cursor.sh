#!/bin/bash

# Swift Selena MCP Server を Cursor に登録するスクリプト
# Cursor CLI（cursor-agent）には MCP 登録コマンドが無いため、設定 JSON を直接編集する
# Usage: ./scripts/register-cursor.sh [target-project-directory]
#        引数なし: 全プロジェクト共通の ~/.cursor/mcp.json に登録
#        引数あり: 対象プロジェクトの .cursor/mcp.json に登録

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Swift Selena → Cursor 登録${NC}"
echo "=============================="

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

# 登録先の設定ファイル（引数があればプロジェクト単位、なければ全プロジェクト共通）
if [ $# -ge 1 ] && [ -n "$1" ]; then
    TARGET_PROJECT="${1/#\~/$HOME}"
    if [ ! -d "$TARGET_PROJECT" ]; then
        echo -e "${RED}エラー: ターゲットディレクトリが見つかりません${NC}"
        echo "パス: $TARGET_PROJECT"
        exit 1
    fi
    CONFIG_DIR="$( cd "$TARGET_PROJECT" && pwd )/.cursor"
    SCOPE_LABEL="プロジェクト単位（$CONFIG_DIR/mcp.json）"
else
    CONFIG_DIR="$HOME/.cursor"
    SCOPE_LABEL="全プロジェクト共通（$CONFIG_DIR/mcp.json）"
fi
CONFIG_FILE="$CONFIG_DIR/mcp.json"

echo ""
echo "登録先: $SCOPE_LABEL"

# jq が無いと既存設定を安全に編集できない
if ! command -v jq &> /dev/null; then
    echo -e "${RED}エラー: jq がインストールされていません${NC}"
    echo "インストール: brew install jq"
    echo ""
    echo "手動で設定ファイルを編集してください："
    echo "  $CONFIG_FILE"
    echo ""
    echo "mcpServers に以下を追加してください："
    echo ""
    echo '    "swift-selena": {'
    echo '      "type": "stdio",'
    echo "      \"command\": \"$EXECUTABLE_PATH\","
    echo '      "env": { "MCP_CLIENT_ID": "cursor" }'
    echo '    }'
    exit 1
fi

mkdir -p "$CONFIG_DIR"

if [ -f "$CONFIG_FILE" ]; then
    # 既存設定を保持したまま swift-selena を追加/更新（バックアップを残す）
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
    echo -e "${GREEN}✓${NC} バックアップ作成: ${CONFIG_FILE}.backup"
    jq --arg path "$EXECUTABLE_PATH" \
        '.mcpServers."swift-selena" = {"type": "stdio", "command": $path, "env": {"MCP_CLIENT_ID": "cursor"}}' \
        "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo -e "${GREEN}✓${NC} 設定ファイルを更新しました（既存設定を保持）"
else
    cat > "$CONFIG_FILE" <<EOF
{
  "mcpServers": {
    "swift-selena": {
      "type": "stdio",
      "command": "$EXECUTABLE_PATH",
      "env": { "MCP_CLIENT_ID": "cursor" }
    }
  }
}
EOF
    echo -e "${GREEN}✓${NC} 設定ファイルを作成しました"
fi

echo ""
echo -e "${GREEN}登録完了！${NC}"
echo ""
echo "次のステップ:"
echo "1. Cursor を再起動するか、Customize サイドバーで swift-selena を有効にしてください"
echo "2. チャットの Available Tools に swift-selena が表示されれば接続できています"
echo ""
echo "設定ファイル: $CONFIG_FILE"
