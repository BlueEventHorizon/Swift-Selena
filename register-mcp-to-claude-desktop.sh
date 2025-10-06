#!/bin/bash

# Swift Selena MCP ServerをClaude Desktopに登録するスクリプト

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 現在のディレクトリを取得
CURRENT_DIR="$(pwd)"
EXECUTABLE_PATH="${CURRENT_DIR}/.build/release/Swift-Selena"

echo -e "${YELLOW}Swift Selena MCP Server 登録スクリプト${NC}"
echo "================================"

# 実行ファイルの存在確認
if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo -e "${RED}エラー: Swift-Selena が見つかりません${NC}"
    echo "パス: $EXECUTABLE_PATH"
    echo ""
    echo "まず 'swift build' を実行してください"
    exit 1
fi

echo -e "${GREEN}✓${NC} 実行ファイルが見つかりました"
echo "  パス: $EXECUTABLE_PATH"

# Claude設定ファイルのパス
CONFIG_DIR="$HOME/Library/Application Support/Claude"
CONFIG_FILE="$CONFIG_DIR/claude_desktop_config.json"

# ディレクトリ作成
mkdir -p "$CONFIG_DIR"

# 既存の設定ファイルを読み込むか、新規作成
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${GREEN}✓${NC} 既存の設定ファイルが見つかりました"
    
    # バックアップ作成
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
    echo -e "${GREEN}✓${NC} バックアップ作成: ${CONFIG_FILE}.backup"
    
    # jqがインストールされているか確認
    if command -v jq &> /dev/null; then
        # jqで既存の設定を保持しつつswift-selenaを追加/更新
        jq --arg path "$EXECUTABLE_PATH" \
            '.mcpServers."swift-selena" = {"command": $path}' \
            "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
        mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        echo -e "${GREEN}✓${NC} 設定ファイルを更新しました（既存設定を保持）"
    else
        echo -e "${YELLOW}警告: jq がインストールされていません${NC}"
        echo "手動で設定ファイルを編集してください："
        echo ""
        echo "  nano \"$CONFIG_FILE\""
        echo ""
        echo "以下を追加してください："
        echo ""
        echo '  "swift-selena": {'
        echo "    \"command\": \"$EXECUTABLE_PATH\""
        echo '  }'
        exit 1
    fi
else
    echo -e "${YELLOW}新規設定ファイルを作成します${NC}"
    
    # 新規作成
    cat > "$CONFIG_FILE" <<EOF
{
  "mcpServers": {
    "swift-selena": {
      "command": "$EXECUTABLE_PATH"
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
echo "1. Claude Desktop を再起動してください"
echo "2. Claude Desktop で以下を試してください:"
echo "   'Swift MCPサーバーに接続できていますか？'"
echo ""
echo "設定ファイル: $CONFIG_FILE"
