# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Swift-Selena = MCP Server for Swift code analysis (Swift Package)

## AI Interaction Language [MANDATORY]

**すべての対話は日本語で実施すること**
- 技術用語・英単語はそのまま使用可能
- ソースコードのコメントも必ず日本語で記述

## Required Reading [MANDATORY]

### 作業タスク実施の基本フロー

```
作業タスクを受け取る
    ↓
docs-advisor Subagent でルール文書を特定
    subagent_type: docs-advisor
    prompt: [タスク内容]
    ↓
project-advisor Subagent で要件定義書・設計書を特定
    subagent_type: project-advisor
    prompt: [タスク内容]
    ↓
必要となる文書セット**全て**読む（または、subagentに渡す）
    ↓
作業タスクを実行
```

## Project Overview

macOS SwiftUI app template for AI-powered development with Clean Architecture and Actor-based concurrency.

## 開発言語・フレームワーク

Package.swift に定義されたプラットフォーム・バージョンで利用可能な技術を使用。
- **macOS**: 13.0+
- **Swift**: 5.9
- **Type**: Swift Package (MCP Server)

## Critical Documentation Structure

```text
project/
├── project_toc.yaml     # 要件定義書・設計書検索インデックス（YAML形式）
└── {feature}/           # Feature単位のディレクトリ（main, 0.6.5等）
    ├── spec/            # 要件定義書（ID体系: REQ-/APP-/SCR-/CMP-/FNC-/BL-/NF-/DM-/EXT-/NAV-）
    ├── design/          # 設計書（ID体系: DES-XXX）
    └── plan/            # 開発計画（{feature}_plan.md）

docs/
├── docs_toc.md          # ルール文書インデックス（docs-advisor Subagent経由で参照）
├── rules/base/          # 基本ルール（project_rule, coding_rule, review_criteria等）
├── workflow/plan/       # 計画フェーズワークフロー（design_workflow, planning_workflow）
└── format/              # 文書フォーマット仕様（spec_format.md, plan_format.md, design_format.md）
```

## Architecture Deep Dive

### Swift-Selena MCP Server アーキテクチャ

```
Sources/
├── SwiftMCPServer.swift     # MCPサーバーエントリーポイント
├── Constants.swift          # 定数定義
├── Logging/                 # ロギング機能
├── Selena/                  # コア解析エンジン
│   ├── FileSearcher         # ファイル検索
│   ├── SwiftSyntaxAnalyzer  # AST解析
│   └── ProjectMemory        # キャッシュ管理
└── Tools/                   # MCPツール実装
    ├── Analysis/            # コード解析ツール
    ├── FileSystem/          # ファイル操作ツール
    ├── Meta/                # メタツール（list_available_tools等）
    ├── Project/             # プロジェクト管理ツール
    ├── SwiftUI/             # SwiftUI解析ツール
    ├── Symbols/             # シンボル解析ツール
    └── ToolProtocol.swift   # ツール共通プロトコル
```

### MCPサーバーの動作フロー

```
Claude/Client
    ↓ JSON-RPC over stdio
SwiftMCPServer (MCP SDK)
    ↓ ツール呼び出し
Tool実装 (ToolProtocol準拠)
    ↓ 解析処理
Selena解析エンジン
    ↓ 結果
ProjectMemory (キャッシュ)
    ↓ レスポンス
Claude/Client
```

**重要原則**:
- 全ツールはToolProtocolに準拠
- SwiftSyntaxによる静的解析（ビルド不要）
- LSP統合によるセマンティック解析（ビルド可能時）

## Build Commands

```bash
# Build
swift build

# Test execution
swift test

# Release build
swift build -c release
```


## Important Constraints [MANDATORY]

### 必須遵守事項
- **NEVER modify Package.swift** without explicit permission
- **Japanese comments required** in source code（全コードコメントは日本語）
- **要件定義書（project/{feature}/spec/**/*.md）が最優先**（すべてのドキュメントに優先）
- **Use existing utilities** before creating new ones (Tools/, Library/)
- **Always update documentation** when making specification changes
- **ファイルヘッダーのCreated by**: git config user.nameの値を使用（生成AIではない）
- **project_toc.yaml 自動更新**: project/{feature}/spec/、project/{feature}/design/ 配下のファイルを追加・変更・削除・移動したら、`project-toc-updater` Subagent を起動して project_toc.yaml を更新すること

### MCP Server実装原則
- **ToolProtocol準拠**: 新規ツールは`ToolProtocol`を実装
- **静的解析優先**: SwiftSyntaxベースの解析を基本とし、LSPは補助的に使用
- **キャッシュ活用**: 解析結果はProjectMemoryでキャッシュ
- **エラーハンドリング**: ツール実行エラーは適切にMCP応答として返却

## MCP活用 [MANDATORY]

### Swift-Selena MCP（推奨・高速）
**活用シーン**:
- **実装前**: 既存の類似実装を検索、重複防止
- **リファクタリング**: 型・シンボルの使用箇所を全検索、変更漏れ防止
- **アーキテクチャ確認**: レイヤー違反検出、プロトコル準拠確認
- **コード理解**: シンボル単位で効率的に読み込み、プロジェクト構造把握
- **知見蓄積**: 重要な仕様・設計をメモとして保存・検索

**未接続時の代替**: Grep/Globツール（速度低下、精度低下）

### Gemini MCP
- OSフレームワーク使い方確認
- 外部API利用方法調査
- Web検索（Google検索）


## Critical Implementation Constraints

### Sources/Tools/ - ツール実装制約
- **ToolProtocol準拠**: 全ツールは`Sources/Tools/ToolProtocol.swift`に準拠
- **カテゴリ配置**:
  - `Analysis/` - コード解析（imports, type hierarchy等）
  - `FileSystem/` - ファイル操作（find_files, search_code等）
  - `Symbols/` - シンボル解析（list_symbols, find_symbol_definition等）
  - `SwiftUI/` - SwiftUI固有解析（property wrappers, protocol conformances等）
  - `Meta/` - メタツール（list_available_tools, get_tool_schema等）
  - `Project/` - プロジェクト管理（initialize_project等）
- **エラーハンドリング**: 解析エラーは適切なエラーメッセージとしてMCP応答に含める

### Sources/Selena/ - コア解析エンジン制約
- **FileSearcher**: ファイルシステムベースの高速検索
- **SwiftSyntaxAnalyzer**: SwiftSyntaxによる静的解析（ビルド不要）
- **ProjectMemory**: 解析結果のキャッシュ管理（永続化対応）

### Code Header Format [MANDATORY]
- **ALWAYS add/update Code Header Format** when creating/modifying Swift files
- **Required marker**: `[Code Header Format]` at the beginning of header comment
- **Required sections**:
  - 目的: このファイルの役割（2-4項目、各1行、簡潔に）
  - 主要機能: 提供する機能（2-5項目、各1行、簡潔に）
  - 含まれる型: このファイルで定義される型（存在する場合のみ）
  - 関連型: 依存する外部型（存在する場合のみ）
- **Format spec**: `docs/format/code_header_format.md`
- **Auto-generate command**: `/create-code-headers --changed` (git変更ファイルのみ)
- **Verification**: Check for `[Code Header Format]` marker in all modified Swift files before task completion

## important-instruction-reminders

Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.

---

## 一時メモ（TODO: 後で削除）

### Codex MCP モデル指定の問題（2025-12-31）

| モデル | 結果 |
|--------|------|
| `o3` | 応答なし |
| `gpt-5.2` | AbortError |
| `gpt-5.2-codex` | ✅ 正常応答 |
| 指定なし | ✅ 正常応答 |

- スキーマには `"o3", "o4-mini"` が例として記載されているが動作せず
- `gpt-5.2-codex` または指定なしで使用すること
