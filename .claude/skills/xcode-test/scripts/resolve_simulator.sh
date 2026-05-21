#!/bin/bash

# iOS シミュレーター検出・起動スクリプト（SKILL用）
#
# 使用方法:
#   resolve_simulator.sh
#
# 出力:
#   起動中（または起動した）シミュレーターの UUID を標準出力に返す
#   シミュレーターが見つからない場合は exit 1

set -e

# 1. 起動中の iPhone シミュレーターを検出
BOOTED=$(xcrun simctl list devices booted 2>/dev/null | grep "iPhone" | head -1)

if [ -n "$BOOTED" ]; then
    # 起動中のシミュレーターから UUID を抽出
    DEVICE_ID=$(echo "$BOOTED" | grep -oEi '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
    if [ -n "$DEVICE_ID" ]; then
        echo "$DEVICE_ID"
        exit 0
    fi
fi

# 2. 起動中のシミュレーターがない場合、利用可能な iPhone を検索して起動
# 最新世代を優先（リスト末尾が最新）
AVAILABLE=$(xcrun simctl list devices available 2>/dev/null | grep "iPhone" | grep -v "Plus\|Pro Max" | tail -1)

if [ -n "$AVAILABLE" ]; then
    DEVICE_ID=$(echo "$AVAILABLE" | grep -oEi '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
    DEVICE_NAME=$(echo "$AVAILABLE" | sed 's/(.*//' | xargs)

    if [ -n "$DEVICE_ID" ]; then
        echo "起動中: $DEVICE_NAME ($DEVICE_ID)" >&2
        xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true  # Already booted は無視
        if xcrun simctl bootstatus "$DEVICE_ID" -b 2>/dev/null; then
            echo "$DEVICE_ID"
            exit 0
        else
            echo "⚠️ bootstatus 未対応環境、3秒待機..." >&2
            sleep 3
            echo "$DEVICE_ID"
            exit 0
        fi
    fi
fi

# 3. 見つからない場合
echo "❌ 利用可能な iPhone シミュレーターが見つかりません" >&2
echo "" >&2
echo "利用可能なデバイス一覧:" >&2
xcrun simctl list devices available 2>/dev/null | grep "iPhone" | head -10 | sed 's/^/   /' >&2
exit 1
