---
name: test
description: |
  Xcode プロジェクトのテストを実行し、失敗を構造化して報告する。iOS/macOS を scheme から自動判定。
  トリガー: "テスト", "test", "テストして", "テスト実行", "ユニットテスト"
user-invocable: true
allowed-tools: Bash, Read, AskUserQuestion
argument-hint: "[scheme-name] [test-target]"
---

# /xcode:test

Xcodeプロジェクトのテストを実行する。

## コマンド構文

```
/xcode:test [scheme-name] [test-target]
```

| 引数        | 内容                                                              |
| ----------- | ----------------------------------------------------------------- |
| scheme-name | スキーム名（省略時は `.xcodeproj` から自動検出）                  |
| test-target | テストターゲット（例: `LibraryTests/FooTests`。省略時は全テスト） |

---

## Step 1: プラットフォーム判定 [MANDATORY]

以下の順序でプラットフォームを判定する:

1. プロジェクト内の `.xcconfig` ファイルから `SDKROOT` を検索:

```bash
grep -r "^SDKROOT" . --include="*.xcconfig" | head -5
```

2. 見つかった場合、`SDKROOT` の値でプラットフォームを決定:

| SDKROOT    | プラットフォーム |
| ---------- | ---------------- |
| `iphoneos` | iOS              |
| `macosx`   | macOS            |

3. `.xcconfig` が見つからない場合: AskUserQuestion で iOS / macOS を確認
4. `SDKROOT` が上記以外の値の場合: AskUserQuestion で確認

---

## Step 2: スキーム・テストターゲット決定

`$ARGUMENTS` を解析する:

| パターン                      | スキーム                  | テストターゲット        |
| ----------------------------- | ------------------------- | ----------------------- |
| 引数なし                      | `.xcodeproj` から自動検出 | 全テスト                |
| `MyApp`                       | `MyApp`                   | 全テスト                |
| `MyApp LibraryTests/FooTests` | `MyApp`                   | `LibraryTests/FooTests` |

スキーム自動検出:

```bash
find . -maxdepth 1 -name "*.xcodeproj" -type d | head -1 | xargs -I{} basename {} .xcodeproj
```

検出できない場合は AskUserQuestion で確認。

---

## Step 3: テスト環境セットアップ

### iOS の場合

シミュレーター検出スクリプトを実行する:

```bash
DEVICE_ID=$(${CLAUDE_PLUGIN_ROOT}/skills/test/scripts/resolve_simulator.sh)
```

- **成功（exit 0）**: stdout に UUID が返る → `{DEVICE_ID}` として使用
- **失敗（exit 1）**: stderr にエラーメッセージと利用可能なデバイス一覧が表示される → AskUserQuestion でデバイスを選択してもらい、手動で UUID を指定

### macOS の場合

セットアップ不要。次の Step へ進む。

---

## Step 4: テスト実行

テストスクリプトを実行する。タイムアウトは **600000ms**（10分）を設定すること。

### macOS

```bash
${CLAUDE_PLUGIN_ROOT}/skills/test/scripts/test.sh "{SCHEME}" "platform=macOS"
```

### iOS（テストターゲット指定あり）

```bash
${CLAUDE_PLUGIN_ROOT}/skills/test/scripts/test.sh "{SCHEME}" "id={DEVICE_ID}" --sdk iphonesimulator --only-testing "{TEST_TARGET}"
```

### iOS（全テスト）

```bash
${CLAUDE_PLUGIN_ROOT}/skills/test/scripts/test.sh "{SCHEME}" "id={DEVICE_ID}" --sdk iphonesimulator
```

---

## Step 5: 結果報告

- **全テスト成功**: スクリプト出力の成功件数を報告
- **テスト失敗**: スクリプト出力のエラー内容を分析し、修正案を提示
