#!/bin/bash

# Xcodeプロジェクト テストスクリプト（SKILL用）
#
# 使用方法:
#   test.sh <scheme> <destination> [--only-testing <target>] [--sdk <sdk>]
#
# 例:
#   test.sh TemplateApp "platform=macOS"
#   test.sh TemplateApp "platform=macOS" --only-testing LibraryTests/FooTests
#   test.sh MyApp "id=DEVICE-UUID" --sdk iphonesimulator

set -e
set -o pipefail

# Bash ツールのカレントディレクトリ（ユーザーのプロジェクトルート）でそのまま実行する
SCHEME="$1"
DESTINATION="$2"
shift 2 || true

# オプション引数の解析
ONLY_TESTING_VAL=""
SDK_VAL=""
while [ $# -gt 0 ]; do
    case "$1" in
        --only-testing)
            if [ -z "$2" ] || [[ "$2" == --* ]]; then
                echo "❌ Error: --only-testing にはテストターゲットを指定してください"
                echo "Usage: test.sh <scheme> <destination> [--only-testing <target>] [--sdk <sdk>]"
                exit 1
            fi
            ONLY_TESTING_VAL="$2"
            shift 2
            ;;
        --sdk)
            if [ -z "$2" ] || [[ "$2" == --* ]]; then
                echo "❌ Error: --sdk には SDK 名を指定してください"
                echo "Usage: test.sh <scheme> <destination> [--only-testing <target>] [--sdk <sdk>]"
                exit 1
            fi
            SDK_VAL="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [ -z "$SCHEME" ] || [ -z "$DESTINATION" ]; then
    echo "❌ Error: scheme と destination は必須です"
    echo "Usage: test.sh <scheme> <destination> [--only-testing <target>] [--sdk <sdk>]"
    exit 1
fi

# 一時ファイルのクリーンアップ（異常終了時にも実行）
TEST_LOG=$(mktemp)
FAILED_TESTS_LOG=$(mktemp)
trap 'rm -f "$TEST_LOG" "$FAILED_TESTS_LOG"' EXIT

echo "Xcode Test"
echo "===================================="
echo "Scheme: $SCHEME"
echo "Destination: $DESTINATION"
[ -n "$ONLY_TESTING_VAL" ] && echo "Target: $ONLY_TESTING_VAL"
[ -n "$SDK_VAL" ] && echo "SDK: $SDK_VAL"

# オプション引数を配列で構築（クォートを保持しつつ安全に展開）
SDK_ARGS=()
[ -n "$SDK_VAL" ] && SDK_ARGS=(-sdk "$SDK_VAL")

ONLY_TESTING_ARGS=()
[ -n "$ONLY_TESTING_VAL" ] && ONLY_TESTING_ARGS=(-only-testing:"$ONLY_TESTING_VAL")

# 1. テスト実行（ログ保存 + フィルタリング）
echo ""
echo "Step 1: Running tests..."
echo "--------------------------------"

set +e
xcodebuild test \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    "${SDK_ARGS[@]}" \
    "${ONLY_TESTING_ARGS[@]}" \
    -skipPackagePluginValidation \
    2>&1 | tee "$TEST_LOG" > /dev/null
TEST_EXIT=${PIPESTATUS[0]}
set -e

# フィルタリング表示（ログ後処理）
grep -iE "(Test Case|error:|warning:|BUILD FAILED|BUILD SUCCEEDED|passed|failed)" "$TEST_LOG" | head -100 || true

# 2. テスト結果の解析（ログファイルから確実に判定）
echo ""
echo "===================================="
echo "Test Results"
echo "===================================="

# 失敗したテストを抽出（大文字小文字を無視）
grep -i "Test Case.*failed" "$TEST_LOG" > "$FAILED_TESTS_LOG" 2>/dev/null || true

# 成功と失敗をカウント（大文字小文字を無視）
FAILED_COUNT=$(wc -l < "$FAILED_TESTS_LOG" | xargs)
PASSED_COUNT=$(grep -ci "Test Case.*passed" "$TEST_LOG" 2>/dev/null || echo "0")

echo "📊 テスト実行結果:"
echo "   ✅ 成功: $PASSED_COUNT tests"
echo "   ❌ 失敗: $FAILED_COUNT tests"

# 失敗したテストの詳細を表示
if [ "$FAILED_COUNT" -gt 0 ]; then
    echo ""
    echo "❌ 失敗したテスト:"
    sed 's/^/   /' "$FAILED_TESTS_LOG"

    echo ""
    echo "💡 失敗の詳細（エラーメッセージ）:"
    grep -iB 2 -A 5 "failed" "$TEST_LOG" | grep -iE "(error|failed|Expected|Actual)" | head -30 | sed 's/^/   /'
fi

# 3. 結果サマリー
echo ""
echo "===================================="
echo "Test Summary"
echo "===================================="

if [ "$FAILED_COUNT" -eq 0 ] && [ "$TEST_EXIT" -eq 0 ] && grep -qiE "TEST SUCCEEDED|passed" "$TEST_LOG"; then
    echo "✅ All tests passed successfully!"
    exit 0
else
    echo "❌ Tests failed: $FAILED_COUNT test(s)"
    exit 1
fi
