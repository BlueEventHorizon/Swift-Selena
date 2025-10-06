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
    echo "まず 'swift build -c release' を実行してください"
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

echo -e "${GREEN}✓${NC} ターゲットプロジェクト確認"
echo "  パス: $TARGET_PROJECT"

# .claudeディレクトリ作成
CONFIG_DIR="${TARGET_PROJECT}/.claude"
CONFIG_FILE="${CONFIG_DIR}/mcp_config.json"

mkdir -p "$CONFIG_DIR"

# 既存の設定ファイルを読み込むか、新規作成
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${GREEN}✓${NC} 既存の設定ファイルが見つかりました"

    # jqがインストールされているか確認
    if command -v jq &> /dev/null; then
        # jqで既存の設定を保持しつつswift-selenaを追加/更新
        jq --arg path "$EXECUTABLE_PATH" \
            '.mcpServers["swift-selena"] = {"command": $path}' \
            "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && \
            mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        echo -e "${GREEN}✓${NC} 既存設定を保持してswift-selenaを更新"
    else
        echo -e "${YELLOW}警告: jqがインストールされていません${NC}"
        echo "既存の設定を上書きします。バックアップを作成中..."
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
        echo -e "${GREEN}✓${NC} バックアップ作成: ${CONFIG_FILE}.backup"

        # 新しい設定で上書き
        cat > "$CONFIG_FILE" <<EOF
{
  "mcpServers": {
    "swift-selena": {
      "command": "$EXECUTABLE_PATH"
    }
  }
}
EOF
    fi
else
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
    echo -e "${GREEN}✓${NC} 設定ファイルを作成"
fi

echo ""
echo -e "${GREEN}登録完了！${NC}"
echo ""
echo "ターゲットプロジェクト: $TARGET_PROJECT"
echo "設定ファイル: $CONFIG_FILE"
echo ""
echo "次のステップ:"
echo "1. ターゲットプロジェクトでClaude Codeを開く"
echo "   cd $TARGET_PROJECT"
echo "   code ."
echo "2. Claude Codeでswift-selenaツールが利用可能になります"
echo ""
echo "使い方:"
echo "  まず initialize_project ツールでプロジェクトを初期化してください"
