#!/bin/bash

# Xcodeプロジェクト ビルドスクリプト（SKILL用）
#
# 使用方法:
#   build.sh <scheme> <destination>
#
# 例:
#   build.sh TemplateApp "platform=macOS"
#   build.sh MyApp "generic/platform=iOS"

set -e
set -o pipefail

# Bash ツールのカレントディレクトリ（ユーザーのプロジェクトルート）でそのまま実行する
SCHEME="$1"
DESTINATION="$2"

if [ -z "$SCHEME" ] || [ -z "$DESTINATION" ]; then
    echo "❌ Error: scheme と destination は必須です"
    echo "Usage: build.sh <scheme> <destination>"
    exit 1
fi

# 一時ファイルのクリーンアップ（異常終了時にも実行）
BUILD_LOG=$(mktemp)
trap 'rm -f "$BUILD_LOG"' EXIT

echo "Xcode Build"
echo "===================================="
echo "Scheme: $SCHEME"
echo "Destination: $DESTINATION"

# 1. クリーンビルド
echo ""
echo "Step 1: Clean..."
xcodebuild clean -scheme "$SCHEME" -destination "$DESTINATION" -quiet || true

# 2. ビルド実行（ログ保存 + フィルタリング）
echo ""
echo "Step 2: Build..."
echo "--------------------------------"

set +e
xcodebuild build \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -skipPackagePluginValidation \
    2>&1 | tee "$BUILD_LOG" > /dev/null
BUILD_EXIT=${PIPESTATUS[0]}
TEE_EXIT=${PIPESTATUS[1]}
set -e

if [ "$TEE_EXIT" -ne 0 ]; then
    echo "❌ Error: ログファイルへの書き込みに失敗しました（ディスク容量等を確認してください）"
    exit 1
fi

# フィルタリング表示（ログ後処理）
grep -E "(error:|warning:|note:|BUILD FAILED|BUILD SUCCEEDED)" "$BUILD_LOG" | head -100 || true

# 3. 結果判定（ログファイルから確実に判定）
echo ""
echo "===================================="
echo "Build Result"
echo "===================================="

if grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
    echo "✅ BUILD SUCCEEDED"
    exit 0
elif [ "$BUILD_EXIT" -ne 0 ] || grep -q "BUILD FAILED" "$BUILD_LOG" || grep -q "error:" "$BUILD_LOG"; then
    echo "❌ BUILD FAILED"
    echo ""
    echo "エラー詳細:"
    grep -E "error:" "$BUILD_LOG" | head -30 | sed 's/^/   /'
    exit 1
else
    echo "⚠️ ビルド結果を判定できません"
    echo "ログ末尾:"
    tail -20 "$BUILD_LOG" | sed 's/^/   /'
    exit 1
fi
