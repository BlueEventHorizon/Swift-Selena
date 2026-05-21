---
name: build
description: |
  Xcode プロジェクトをビルドし、エラーを構造化して報告する。iOS/macOS を scheme から自動判定。
  トリガー: "ビルド", "build", "ビルドして", "コンパイルエラー確認"
user-invocable: true
allowed-tools: Bash, Read, AskUserQuestion
argument-hint: "[scheme-name]"
---

# /xcode:build

Xcodeプロジェクトのフルビルドを実行する。

## コマンド構文

```
/xcode:build [scheme-name]
```

| 引数        | 内容                                             |
| ----------- | ------------------------------------------------ |
| scheme-name | スキーム名（省略時は `.xcodeproj` から自動検出） |

---

## Step 1: プラットフォーム判定 [MANDATORY]

以下の順序でプラットフォームを判定する:

1. プロジェクト内の `.xcconfig` ファイルから `SDKROOT` を検索:

```bash
grep -r "^SDKROOT" . --include="*.xcconfig" | head -5
```

2. 見つかった場合、`SDKROOT` の値でプラットフォームを決定:

| SDKROOT    | プラットフォーム | destination            |
| ---------- | ---------------- | ---------------------- |
| `iphoneos` | iOS              | `generic/platform=iOS` |
| `macosx`   | macOS            | `platform=macOS`       |

3. `.xcconfig` が見つからない場合: AskUserQuestion で iOS / macOS を確認
4. `SDKROOT` が上記以外の値の場合: AskUserQuestion で確認

---

## Step 2: スキーム決定

1. `$ARGUMENTS` にスキーム名が指定されていればそのまま使用
2. 未指定の場合、プロジェクトルートの `.xcodeproj` ディレクトリ名から推定:

```bash
find . -maxdepth 1 -name "*.xcodeproj" -type d | head -1 | xargs -I{} basename {} .xcodeproj
```

検出できない場合は AskUserQuestion で確認。

---

## Step 3: ビルド実行

ビルドスクリプトを実行する。タイムアウトは **300000ms**（5分）を設定すること。

```bash
${CLAUDE_PLUGIN_ROOT}/skills/build/scripts/build.sh "{SCHEME}" "{DESTINATION}"
```

- `{SCHEME}`: Step 2 で決定したスキーム名
- `{DESTINATION}`: Step 1 で決定した destination

---

## Step 4: 結果報告

- **ビルド成功**: 成功を簡潔に報告
- **ビルド失敗**: スクリプト出力のエラー内容を分析し、修正案を提示
