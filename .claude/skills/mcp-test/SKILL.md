---
name: mcp-test
description: >
  Swift-Selena MCP サーバーの全ツールを自動テストする。
  debug ビルド → initialize_project → 全ツール実行 → 結果サマリー。
  Use when: "MCPテスト", "ツールテスト", "MCP動作確認", "/mcp-test"
---

# MCP Test

Swift-Selena MCP サーバーに接続し、全ツールの動作を自動検証する。

## 前提条件

- `swift-selena-debug` MCP サーバーが Claude Code の MCP 設定に登録済みであること
- MCP ツール `mcp__swift-selena-debug__*` が利用可能であること

## ワークフロー

### Step 1: Debug ビルド

```bash
swift build
```

ビルド失敗 → エラーを報告して終了。

### Step 2: プロジェクト初期化

```
mcp__swift-selena-debug__initialize_project
  project_path: <プロジェクトルートの絶対パス>
```

確認ポイント:
- "Project initialized" メッセージが返ること
- LSP 接続状態（available / unavailable）を記録

### Step 3: ツール一覧取得

```
mcp__swift-selena-debug__list_available_tools
```

返されたツール一覧を記録し、Step 4 のテスト対象とする。

### Step 4: 全ツールのテスト実行

各ツールを適切なパラメータで実行する。並列実行可能なものは並列で呼び出す。

#### テストケース定義

| ツール | テストパラメータ | 成功判定 |
|--------|-----------------|----------|
| `find_files` | `pattern: "*.swift"` | 1件以上のファイルが返る |
| `search_code` | `pattern: "import", file_pattern: "*.swift"` | マッチが返る（file_pattern 修正の検証を兼ねる） |
| `search_files_without_pattern` | `pattern: "ToolProtocol", file_pattern: "*.swift"` | パターン不含ファイルが返る |
| `list_symbols` | `file_path:` Sources/ 配下の任意の .swift ファイル | シンボル一覧が返る |
| `find_symbol_definition` | `symbol_name:` プロジェクト内の既知の型名 | 定義箇所が返る |
| `list_property_wrappers` | `file_path:` Tests/Fixtures/TestSwiftUIView.swift | @State 等が検出される |
| `list_protocol_conformances` | `file_path:` Tests/Fixtures/TestProtocolConformance.swift | 準拠一覧が返る |
| `list_extensions` | `file_path:` Tests/Fixtures/TestExtension.swift | Extension 一覧が返る |
| `analyze_imports` | `file_path:` Sources/ 配下の任意ファイル | import 依存関係が返る |
| `get_type_hierarchy` | `type_name:` プロジェクト内の既知の型名 | 型階層が返る |
| `find_test_cases` | 引数なし、またはテストファイルを指定 | テストケース一覧が返る |

- テストで使うファイルパスは絶対パスで指定すること
- Fixtures ファイルがない場合は Sources/ 配下のファイルで代替する
- ツールがエラーを返した場合は `get_tool_schema` でパラメータを確認してリトライ

### Step 5: 結果サマリー

全ツールのテスト結果をテーブルで報告する:

```
## MCP テスト結果

| # | ツール | 結果 | 備考 |
|---|--------|------|------|
| 1 | initialize_project | ✅ | LSP: available |
| 2 | find_files | ✅ | 42件検出 |
| ... | ... | ... | ... |

✅ 全N件パス / ❌ N件失敗
```

失敗があった場合:
- エラー内容を記載
- 原因の推測を提示
- 修正が必要な場合は対象ファイルと修正案を提示
