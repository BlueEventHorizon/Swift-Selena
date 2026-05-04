# CLAUDE.md

Swift-Selena = MCP Server for Swift code analysis (Swift Package)

## AI Interaction Language [MANDATORY]

**すべての対話は日本語で実施すること**
- 技術用語・英単語はそのまま使用可能
- ソースコードのコメントも日本語で記述
- ファイル記述も日本語。ただし修正前のファイルがすでに英語記述の場合は、そのまま英語記述

## Important Constraints [MANDATORY]

- **NEVER modify Xcode project files** (`*.xcodeproj/`) without explicit permission
  - 注: フォルダーベース登録済みのため、ファイル追加時は変更不要
- **NEVER modify Info.plist or XCConfig files** without explicit permission
- **要件定義書（specs/{feature}/requirements/）が最優先**（すべてのドキュメントに優先）
- **文書不整合の即時報告**: `rules/`、`specs/`、`.claude/` 内の文書で不整合・矛盾を発見した場合、作業を中断して最優先でユーザーに報告すること
- **Use existing code** before creating new ones (Tools/, Library/)
- **既存コード参考必須**: 新規コード作成前に、既存の類似実装を検索して参考にすること
- **ファイルヘッダーのCreated by**: git config user.nameの値を使用
- **作業開始時の文書検索**: 文書読解が必要な作業は、`/query-rules` `/query-specs` で関連文書を特定し、該当する文書を読んでから作業に入ること
- **ToC 自動更新**: rules/ 配下の文書を追加・変更・削除したら `/create-rules-toc`、specs/{feature}/requirements/ または specs/{feature}/design/ 配下の文書を追加・変更・削除したら `/create-specs-toc` を実行すること
- **ToC ファイル直接編集禁止**: `.claude/doc-advisor/` 配下の ToC ファイルは直接編集せず、`/create-rules-toc` / `/create-specs-toc` で更新すること
- **Swift-Selena MCP の利用検討**: Swift-Selena MCP が接続されている場合、コードの分析・解析作業で MCP の説明から効率的・効果的か判定し、利用を検討すること（実験は不要、MCP の説明で判断）
- **Xcode MCP の利用検討**: Xcode MCP が接続されている場合、Skill（`/xcode:build` / `/xcode:test`）が対応していない場面でのみ、MCP の説明から効果的か判定し、利用を検討すること

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
├── Constants.swift          # 定数定義・環境変数キー
├── Logging/                 # ロギング機能
├── Selena/                  # コア解析エンジン
│   ├── Core/                # コア機能
│   │   ├── FileSearcher.swift       # ファイルシステムベースの高速検索
│   │   ├── SwiftSyntaxAnalyzer.swift# AST解析（シンボル・型・Import等）
│   │   └── ProjectMemory.swift      # 解析結果のキャッシュ管理（永続化）
│   ├── Cache/               # キャッシュ管理
│   │   ├── CacheManager.swift
│   │   ├── CacheGarbageCollector.swift
│   │   └── FileCacheEntry.swift
│   ├── LSP/                 # SourceKit-LSP統合（ビルド可能時）
│   │   ├── LSPClient.swift
│   │   └── LSPState.swift
│   ├── Visitors/            # SwiftSyntax訪問者（7種）
│   │   ├── SymbolVisitor.swift
│   │   ├── ImportVisitor.swift
│   │   ├── PropertyWrapperVisitor.swift
│   │   ├── TypeConformanceVisitor.swift
│   │   ├── ExtensionVisitor.swift
│   │   ├── XCTestVisitor.swift
│   │   └── SwiftTestingVisitor.swift
│   └── DebugRunner.swift    # デバッグ用自動実行（DEBUG時のみ）
└── Tools/                   # MCPツール実装
    ├── Analysis/            # コード解析ツール（3ツール）
    ├── FileSystem/          # ファイル操作ツール（3ツール）
    ├── Meta/                # メタツール（3ツール + MetaToolRegistry）
    ├── Project/             # プロジェクト管理ツール（1ツール）
    ├── SwiftUI/             # SwiftUI解析ツール（3ツール）
    ├── Symbols/             # シンボル解析ツール（2ツール）
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
  - `Meta/` - メタツール（list_available_tools, get_tool_schema, execute_tool）＋MetaToolRegistry（レジストリ）
  - `Project/` - プロジェクト管理（initialize_project等）
- **エラーハンドリング**: 解析エラーは適切なエラーメッセージとしてMCP応答に含める

### Sources/Selena/ - コア解析エンジン制約
- **Core/FileSearcher**: ファイルシステムベースの高速検索
- **Core/SwiftSyntaxAnalyzer**: SwiftSyntaxによる静的解析（ビルド不要）、Visitors/配下のVisitorを使用
- **Core/ProjectMemory**: 解析結果のキャッシュ管理（永続化対応）
- **Cache/**: CacheManager・CacheGarbageCollector によるキャッシュライフサイクル管理
- **LSP/**: LSPClient・LSPState による SourceKit-LSP 統合（ビルド可能時のみ利用）
- **Visitors/**: SwiftSyntax の SyntaxVisitor サブクラス群（シンボル・Import・型解析等）

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

