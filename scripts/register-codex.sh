#!/bin/bash

# Swift Selena (RELEASE) を Codex に登録するスクリプト
# Codex CLI の `codex mcp add` で ~/.codex/config.toml に登録する（CLI / IDE 拡張 / デスクトップアプリ共通）
# Usage: ./scripts/register-codex.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Swift Selena (RELEASE) → Codex 登録${NC}"
echo "======================================"

# Codex CLI の存在確認
if ! command -v codex &> /dev/null; then
    echo -e "${RED}エラー: codex コマンドが見つかりません${NC}"
    echo "Codex CLI をインストールしてください（例: npm install -g @openai/codex）"
    exit 1
fi

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

# バイナリのビルド日時を表示
BUILD_TIME=$(stat -f "%Sm" "$EXECUTABLE_PATH")
echo "  ビルド日時: $BUILD_TIME"

echo ""
echo "Codex MCP設定（~/.codex/config.toml）に登録中..."

# 既存の設定を削除（存在する場合）
codex mcp remove swift-selena 2>/dev/null || true

# 新しい設定を追加（MCP_CLIENT_ID でクライアントごとにキャッシュを分離）
set +e
codex mcp add swift-selena --env MCP_CLIENT_ID=codex -- "$EXECUTABLE_PATH"
RESULT=$?
set -e

if [ $RESULT -eq 0 ]; then
    echo ""
    echo -e "${GREEN}登録完了！${NC}"
    echo ""
    echo "次のステップ:"
    echo "1. 'codex mcp list' または Codex 内で '/mcp' を実行して登録を確認"
    echo "2. IDE 拡張を使っている場合は Restart extension を実行"
else
    echo ""
    echo -e "${RED}登録に失敗しました${NC}"
    exit 1
fi
