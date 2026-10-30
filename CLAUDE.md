# CLAUDE.md

Swift-Selena = MCP Server for Swift code analysis (Swift Package)

## AI Interaction Language [MANDATORY]

**すべての対話は日本語で実施すること**
- 技術用語・英単語はそのまま使用可能
- ソースコードのコメントも日本語で記述
- ファイル記述も日本語。ただし修正前のファイルがすでに英語記述の場合、またはユーザーからの指定がある場合は、英語記述とする

## Important Constraints [MANDATORY]

- **NEVER modify Xcode project files** (`*.xcodeproj/`) without explicit permission
  - 注: フォルダーベース登録済みのため、ファイル追加時は変更不要
- **NEVER modify Info.plist or XCConfig files** without explicit permission
- **要件定義書（project/{feature}/spec/）が最優先**（すべてのドキュメントに優先）
- **文書不整合の即時報告**: `rules/`、`specs/`、`.claude/` 内の文書で不整合・矛盾を発見した場合、作業を中断して最優先でユーザーに報告すること
- **Use existing code** before creating new ones (Sources/Tools/, Sources/Selena/)
- **既存コード参考必須**: 新規コード作成前に、既存の類似実装を検索して参考にすること
- **ファイルヘッダーのCreated by**: git config user.nameの値を使用
- **作業開始時の文書検索**: 文書読解が必要な作業は、`/forge:query-db-rules` `/forge:query-db-specs` で関連文書を特定し、該当する文書を読んでから作業に入ること
- **DB インデックス自動更新**: docs/ 配下の文書を追加・変更・削除したら `/forge:update-db-rules`、project/{feature}/spec/ または project/{feature}/design/ 配下の文書を追加・変更・削除・移動したら `/forge:update-db-specs` を実行すること（索引の対象範囲は `.doc_structure.yaml` が定義）
- **DB インデックス直接編集禁止**: `.claude/doc-advisor/` および `.claude/doc-db/` 配下のインデックスファイルは直接編集せず、`/forge:update-db-rules` / `/forge:update-db-specs` で更新すること
- **Swift-Selena MCP の利用検討**: Swift-Selena MCP が接続されている場合、コードの分析・解析作業で MCP の説明から効率的・効果的か判定し、利用を検討すること（実験は不要、MCP の説明で判断）
- **Xcode MCP の利用検討**: Xcode MCP が接続されている場合、Skill（`/xcode:build` / `/xcode:test`）が対応していない場面でのみ、MCP の説明から効果的か判定し、利用を検討すること
- **MCP サーバー再起動を伴うテストはユーザー依頼必須**: MCP サーバー（Swift-Selena MCP 等）の再起動を要するエンドツーエンドテスト（コード変更後の挙動確認、キャッシュ破棄を伴う動作確認など）は、**AI が独断で実施せず、必ずユーザーに再起動を依頼してから実施すること**
  - AI 側からは別プロセスである MCP サーバーを再起動できない
  - 再起動が必要な場合は、再起動手順（バイナリ再ビルド要否、必要なキャッシュ削除、確認したい挙動）を明示してユーザーに依頼する
  - ユニットテストでの代替検証で済む場合はそれを優先し、E2E 検証の要否を判断する
- **バージョン表記規約**（Issue #38 で確立。プロジェクト全体で参照すべき正規）:
  - **canonical（真実の源）**: `Sources/Constants.swift` の `AppConstants.version`（例: `"0.6.10"`）。`/forge:update-version` で更新する
  - **git tag**: `MAJOR.MINOR.PATCH` 形式（**`v` プレフィックスなし**、例: `0.6.10`）。既存 16 個の tag と整合
  - **CHANGELOG.md header (新規 entry)**: `## VERSION - YYYY-MM-DD` 形式（**`v` プレフィックスなし**、例: `## 0.6.10 - 2026-05-27`）。過去 entry (`## v0.6.X` 形式) は historical record として遡及修正しない
  - **`.version-config.yaml`** の `tag_format` は `"{version}"`（`v` なし）
  - **例外**: `README.md` / `README.ja.md` 内の「機能 X は v0.6.3 以降で利用可能」等の**機能登場版マーカー**は `v` 付きを許容（独立した文脈表記）
  - **検証**: `scripts/verify_version_consistency.sh` で canonical（`Sources/Constants.swift`）・CHANGELOG 先頭 entry・`.version-config.yaml` の `tag_format` / `version_file` / `version_path` の一致を確認。CI ワークフロー `.github/workflows/version_check.yml` で PR ごとに自動検証
  - **Formula は verify script 対象外**: `Formula/swift-selena.rb` の `tag:` は version 文字列と一致するが、`verify_version_consistency.sh` の必須チェックには含めない。Formula の整合性は後述の `scripts/verify_release_tag.sh`（tag 確定後に検証）と `brew install` 実検証で担保する
- **リリースタグは main の本流（第1親ライン）に作成する**: `{version}` 形式（**`v` プレフィックスなし**）のリリースタグは、必ず **main に version bump をマージした直後の main 先頭 commit** に対して作成すること
  - tag は main の merge commit（または fast-forward 後の先頭 commit）に打つ。これにより tag が main の本流に並ぶ
  - **Formula に `revision:` を書かない**（`tag:` のみ）。tag commit は Formula 自身を含むため、その SHA を Formula に書くことは原理的にできない（循環）。`revision:` を持たなければ「tag と revision の不一致」（Issue #38）は起き得ない
  - `develop` 等の作業ブランチで先行して `git tag` を打たない（main にマージし、main へ checkout してから打つ）
  - タグ作成前に `git branch --show-current` で main に居ること、`git status -sb` で `origin/main` と一致していること（push 済み）を確認する
  - 誤った commit / ブランチで作成したタグは `git tag -d <tag> && git push <remote> :<tag>` で削除し、正しい commit で切り直す
- **release の運用順序（Formula 同梱・単一マージ）**: version bump と Formula の `tag:` 更新を同一 PR に同梱し、main へのマージを **1 回**に集約する。以下の 3 フェーズで実施する
  - **Phase 1 — bump PR（作業ブランチ）**:
    1. `/forge:update-version <target> <patch|minor|major>` を実行（`Sources/Constants.swift` 更新 + CHANGELOG への新規 entry 挿入）し commit
    2. `Formula/swift-selena.rb` の `tag:` を `{version}` に更新（`revision:` は書かない）して commit
    3. `scripts/verify_version_consistency.sh`（version 文字列の一致）+ `brew style Formula/swift-selena.rb`（Formula 文法）でローカル検証
    4. push し、PR を作成・マージ（`develop` 等の作業ブランチ）
  - **Phase 2 — main マージ + tag（main 上）**:
    5. `develop` の変更を `main` にマージ → push（merge の方式は問わない。SHA に依存しないため squash / rebase も可）
    6. `main` に checkout し `git branch --show-current` で確認 → `git tag {version}`（main 先頭）→ `git push <remote> {version}`。**main へのマージ後、速やかに tag を打つ**（Formula の `tag:` が未作成の tag を指す期間を最小にする）
    7. `scripts/verify_release_tag.sh {version}` で「tag が main の第1親ライン上」「tag commit の Constants version == {version}」「Formula `tag:` == {version}」「Formula に `revision:` が無い」を検証（不整合なら `exit 1`）。CI `release_tag_check.yml` でも tag push 時に自動検証される
    8. tap 反映後、`brew install --build-from-source` で実 install 検証（`serverInfo.version == {version}`）
  - **Phase 3 — bottle 反映（任意・tag push 後）**: tag push で `bottle.yml` が bottle をビルドし Release へ添付する（CI は repo へ push しない）
    9. Release に bottle が添付されたことを確認後、`develop` から作業ブランチを作成し `scripts/merge_bottles.sh {version}` を実行 → 変更された Formula を commit
    10. 通常どおり develop → main へマージ（Formula の `tag:` は変更されない。bottle 反映の commit は tag より後ろに入る）
- **既存 release artifact の drift について（documented limitation）**: 本規約は HEAD 以降で commit される変更にのみ適用される。既存 release tag（例: `0.6.10`）のソース内 `AppConstants.version` 等が drift していても、本規約では遡及修正しない（git 履歴の整合性保持）。Homebrew で install される既存 release バイナリの `serverInfo.version` が canonical と一致しない場合、それは「既知の historical drift」として受容し、次回 release で初めて完全整合する

## 開発言語・フレームワーク

Package.swift に定義されたプラットフォーム・バージョンで利用可能な技術を使用。
- **macOS**: 13.0+
- **Swift**: 6.1（`swift-tools-version`。言語モードは `swiftLanguageModes: [.v5]` で Swift 5）
- **Type**: Swift Package (MCP Server)

## Critical Documentation Structure

```text
project/
└── {feature}/           # Feature単位のディレクトリ（現在は main のみ）
    ├── spec/            # 要件定義書（文書ID: REQ-XXX、本文内の項目ID: FR-/NFR-/UC-）
    ├── design/          # 設計書（文書ID: DES-XXX）
    ├── plan/            # 開発計画（{feature}_plan.md）
    └── mcp-guide/       # MCP サーバー開発・MCP Swift SDK の一般メモ

docs/
├── rules/base/          # 基本ルール（project_rule, coding_rule, review_criteria等）
├── workflow/plan/       # 計画フェーズワークフロー（design_workflow, planning_workflow）
└── format/              # 文書フォーマット仕様（spec_format, plan_format, design_format, code_header_format）

.doc_structure.yaml      # docs/ をルール、project/*/{spec,design,plan,mcp-guide}/ を仕様書として宣言
.claude/.doc-advisor/    # /forge:query-db-rules / /forge:query-db-specs が使う検索インデックス（直接編集禁止）
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
│   │   └── ProjectMemory.swift      # 解析結果のキャッシュ管理（永続化・更新時刻による無効化）
│   ├── LSP/                 # SourceKit-LSP統合（.xcodeproj がある場合は無効）
│   │   ├── LSPClient.swift
│   │   └── LSPState.swift
│   ├── Visitors/            # SwiftSyntax Visitor（8種）
│   │   ├── SymbolVisitor.swift
│   │   ├── SymbolVisitorV2.swift
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
    ├── ToolProtocol.swift   # ツール共通プロトコル
    └── ResultEncoder.swift  # ツール結果のエンコード
```

### MCPサーバーの動作フロー

```
Claude/Client
    ↓ JSON-RPC over stdio
SwiftMCPServer (MCP SDK)
    ↓ ツール呼び出し
Tool実装 (MCPTool 準拠)
    ↓ 解析処理
Selena解析エンジン
    ↓ 結果
ProjectMemory (キャッシュ)
    ↓ レスポンス
Claude/Client
```

**重要原則**:
- 新規ツールは MCPTool プロトコルに準拠（既存の例外: `InitializeProjectTool` は SwiftMCPServer が直接呼び出し、`ExecuteToolTool` は `LSPState` を受け取る独自シグネチャ）
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
- **Use existing utilities** before creating new ones (Sources/Tools/, Sources/Selena/)
- **Always update documentation** when making specification changes
- **ファイルヘッダーのCreated by**: git config user.nameの値を使用（生成AIではない）
- **仕様索引の更新**: project/{feature}/spec/、project/{feature}/design/ 配下のファイルを追加・変更・削除・移動したら `/forge:update-db-specs` を実行すること（上記「DB インデックス自動更新」と同じ）

### MCP Server実装原則
- **MCPTool 準拠**: 新規ツールは `MCPTool` プロトコル（`Sources/Tools/ToolProtocol.swift` で定義）を実装
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
- **MCPTool 準拠**: 新規ツールは `Sources/Tools/ToolProtocol.swift` で定義された `MCPTool` プロトコルに準拠（`InitializeProjectTool` と `ExecuteToolTool` は既存の例外）
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
- **Core/ProjectMemory**: 解析結果のキャッシュ管理（`memory.json` に永続化、ファイル更新時刻で無効化）。キャッシュ層はこのファイルのみ
- **LSP/**: LSPClient・LSPState による SourceKit-LSP 統合（プロジェクトルート直下に `.xcodeproj` がある場合は無効。ビルド可否は判定しない）
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

