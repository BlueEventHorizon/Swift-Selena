# Swift-Selena: プロジェクト概要

この文書は、Swift-Selena の開発に参加する人と、文書を書く・直す AI のためのものです。インストールと使い方は `README.md`（日本語）と `README_en.md`（英語）、開発 AI が守るべきルールは `CLAUDE.md` を参照してください。調査時点のバージョンは 0.6.12 です（`Sources/Constants.swift` の `AppConstants.version`）。

## 1. 位置づけ

Swift-Selena は、Swift プロジェクトのコード解析を AI エージェントに提供する MCP（Model Context Protocol）サーバーで、Swift Package として書かれています。クライアントが起動するローカルプロセスとして動き、stdio（JSON-RPC）で通信します。README が挙げるクライアントは Claude Code、Claude Desktop、Cursor、Codex です。必要環境は macOS 13.0 以降で、ビルドには Swift 6.1（Xcode 16.3）以降のツールチェーンが必要です（`Package.swift` の `swift-tools-version: 6.1`。固定された swift-nio 2.98.0 と swift-log 1.12.0 が要求）。言語モードは Swift 5 のままです（`swiftLanguageModes: [.v5]`）。動作確認は Swift 6.4 で行っています。配布は Homebrew tap で、このリポジトリ自体が tap です（`Formula/swift-selena.rb`）。

全体要件（`project/main/spec/REQ-001_Swift_Selena_Overall_Requirements.md`）が挙げる解決対象の課題は次の三つです。

- 実装中のコードはビルドできないことが多く、ビルド成功を前提とするツール（SourceKit-LSP、Xcode）では解析できない。
- ソースコードをローカルマシンの外に出したくない。
- 大規模プロジェクトでも結果が速く返る必要がある。

同じ要件定義書は Serena（多言語対応の汎用 MCP サーバー）、SourceKit-LSP、Xcode と比較しています。独自の価値として挙げているのは、ビルド不要、Swift 特化の解析（SwiftUI の property wrapper、protocol 準拠、extension、テスト）、MCP 統合です。解析対象のプロジェクトに対しては読み取り専用で、プロジェクトのコードの変更もビルドもしません（REQ-001 の 7 章）。自分のキャッシュとログは `~/.swift-selena/` に書き込みます。

## 2. 設計意図と仕組み

### 原則

REQ-001（6.2 節）と開発計画（`project/main/plan/main_plan.md`）に同じ四つの原則があります。

1. **ビルド不要の解析。** 基盤は SwiftSyntax による静的解析です。構文が正しければ、型チェックが通らなくても動きます。
2. **ローカル完結。** ネットワーク通信をしません。解析結果は `~/.swift-selena/` に保存します。
3. **段階的な強化。** SwiftSyntax がベースライン、SourceKit-LSP はオプションの強化です。LSP が使えない、または失敗したときは SwiftSyntax にフォールバックします（グレースフルデグレード）。
4. **運用の現実。** メンテナンスフリーと自動更新（REQ-001 の表現。文書に詳しい説明はありません）。

### リクエストの流れ

```text
Client -> JSON-RPC over stdio -> SwiftMCPServer (MCP SDK)
       -> meta tool (execute_tool) -> a tool conforming to MCPTool
       -> analysis engine (SwiftSyntax / LSP / FileSearcher)
       -> ProjectMemory (cache) -> response
```

- **ツール。** ツール定義は 15 個です。`initialize_project`、解析ツール 11 個、メタツール 3 個です。ツール名は `Sources/Constants.swift` の `ToolNames`（12 個: `initialize_project` と解析ツール 11 個）と `MetaToolNames` に定義され、メタツールが参照するレジストリは `Sources/Tools/Meta/MetaToolRegistry.swift` です。15 個のうち 13 個が `MCPTool` プロトコル（`Sources/Tools/ToolProtocol.swift`）に準拠します。例外は 2 つで、`InitializeProjectTool` は `SwiftMCPServer` が直接呼び出し、`ExecuteToolTool` は `LSPState` を受け取る独自の `execute` を持ち、`switch` で解析ツールに振り分けます。
- **メタツールモード（既定、v0.6.3 以降）。** クライアントに見えるのは `initialize_project`、`list_available_tools`、`get_tool_schema`、`execute_tool` の 4 つだけです。解析ツール 11 個もほかと同じくバイナリにコンパイル済みで、MCP のツール一覧から隠され、`execute_tool` 経由で呼ばれるだけです。これでコンテキストウィンドウの使用量を抑えます。**レガシーモード**（`SWIFT_SELENA_LEGACY=1`）では `ToolNames` の 12 個を直接公開します。
- **解析エンジン。** `SwiftSyntaxAnalyzer` が SwiftSyntax の visitor（シンボル、import、property wrapper、型準拠、extension、XCTest、Swift Testing）で構文木をたどります。`FileSearcher` はファイルシステムを検索します。`LSPClient` と `LSPState` が SourceKit-LSP を扱い、接続は `initialize_project` の後にバックグラウンドで行われます。`LSPState` はプロジェクトがビルドできるかを調べません。プロジェクトルート直下に `.xcodeproj` があるときだけ LSP を無効にします（`Sources/Selena/LSP/LSPState.swift`）。
- **キャッシュ。** キャッシュ層は `ProjectMemory`（`Sources/Selena/Core/ProjectMemory.swift`）だけです。`memory.json` を `~/.swift-selena/clients/` の下に、クライアント（`MCP_CLIENT_ID`）ごと、プロジェクト（パスのハッシュ）ごとに永続化します。無効化はファイルの更新時刻で行います。キャッシュごとにファイル単位のインデックス（シンボルは `fileIndex`、import は `importFileIndex`、型準拠は `typeFileIndex`）を持ち、そのキャッシュを書き込んだときに記録し、読み出すたびに確認します。そのため、あるキャッシュを更新しても、別のキャッシュの古いエントリが最新に見えることはありません。`getTypeHierarchy` は呼び出しのたびに型準拠キャッシュを最新化します。削除されたファイル由来のエントリを捨て、新規または変更されたファイルだけをパースし直します。

詳細な設計は `project/main/design/` の `DES-101`（アーキテクチャ）、`DES-102`（LSP 統合）、`DES-103`（ツール実装）、`DES-104`（`search_code` と `find_symbol_definition` の強化）を参照してください。DES-101 と DES-103 は v0.5.3 時点、DES-102 は LSP 統合フェーズの v0.5.1〜v0.5.5 の状態を記述しています（下の「古さの違う文書」を参照）。

### 文書の優先順位

`project/{feature}/spec/` の要件定義書は、すべての文書より優先します（`CLAUDE.md`、`docs/rules/base/project_rule.md`）。意思決定は人間が行い、AI は要件・設計・計画・コードの作成と変更を行います（`project_rule.md` の 4 章）。

### 古さの違う文書

spec と design の文書は v0.5.x から v0.6.x にかけて段階的に書かれました。いくつかは、すでに存在しない状態（たとえば 18 ツール、`find_symbol_references`、`find_type_usages`、`read_symbol`）を今も記述しています。文書自身が、現行のツール一覧は `Sources/Constants.swift` の `ToolNames` と `MetaToolRegistry.swift` が正だと述べています。ツール一覧はこの二つのファイルを正としてください。ほかにも古さの印があります。REQ-001、DES-101、DES-102、DES-103 のステータスは、以後のバージョンがリリースされた今も「承認待ち」のままです。索引 `project/main/spec/README.md` は REQ-004 を載せておらず、存在しない文書（`DES-007`〜`DES-009` など）を参照しています。REQ-005 は v0.6.8 で REQ-003 に統合されて削除されましたが、複数の文書がいまも REQ-005 を参照しています（経緯は DES-104 にあります）。Code Header DB（REQ-004、DES-006、ツール `search_code_headers` と `get_code_header_stats`）は仕様化されていますが、どちらのツールも `Sources/` にありません。

### リリースとバージョン

正となるバージョンは `AppConstants.version` です。git tag に `v` は付けません。リリースタグは `main` の第 1 親ライン上に打ち、Formula は `tag:` のみを使います（`revision:` は書きません）。正式な手順は `CLAUDE.md` にあり、`DEVELOPMENT.ja.md` に図があります。CI は整合性の検証（`scripts/verify_version_consistency.sh`、`scripts/verify_release_tag.sh`）と、tag push 時の bottle ビルドを行います。`swift build` や `swift test` を実行するワークフローはなく、テストはローカルで実行します。

## 3. 構成

| パス | 役割 |
| --- | --- |
| `README.md`, `README_en.md` | 初めて使う人向けの紹介（日本語と英語）。このリポジトリの英語版 README は現在 `README_en.md` |
| `DEVELOPMENT.md`, `DEVELOPMENT.ja.md` | 開発ガイド。ビルド、テスト、ツール追加、CI、リリース手順 |
| `CLAUDE.md` | 開発 AI が守る必須事項。`AGENTS.md` はこれへのシンボリックリンク、`GEMINI.md` は読み込むだけ |
| `CHANGELOG.md` | リリース履歴（日本語で記述） |
| `Sources/` | サーバー本体。`SwiftMCPServer.swift`（エントリーポイント）、`Constants.swift`、`Logging/`、`Selena/`（解析エンジン: `Core/`、`LSP/`、`Visitors/`（visitor 8 個）、`DebugRunner.swift`）、`Tools/`（`Project/`、`FileSystem/`、`Symbols/`、`SwiftUI/`、`Analysis/`、`Meta/`、`ToolProtocol.swift`、`ResultEncoder.swift`） |
| `Tests/` | テストターゲットと `Tests/Fixtures/`（解析対象のサンプルコード）。`Package.swift` に登録されているのは 4 ターゲット |
| `scripts/`, `makefile`, `Formula/`, `.github/workflows/` | クライアント登録、version と tag の検証、bottle の反映、Homebrew Formula、CI |
| `project/main/spec/` | 要件定義書 `REQ-001`〜`REQ-004` と索引（`README.md`） |
| `project/main/design/` | 設計書 `DES-004`、`DES-005`、`DES-006`、`DES-101`〜`DES-104` |
| `project/main/plan/` | 開発計画（`main_plan.md`） |
| `project/main/mcp-guide/` | MCP サーバー開発と MCP Swift SDK の一般的なメモ（このプロジェクト固有ではない） |
| `docs/rules/base/` | 開発ルール。プロジェクトルール、コーディングルール、レビュー観点、ソフトウェア開発の原則、Agent / MCP 活用ルール |
| `docs/format/` | 要件定義書、設計書、計画書、Code Header のフォーマット |
| `docs/workflow/plan/` | 設計書と計画書を作るワークフロー |
| `.claude/` | このリポジトリ自身の AI 用設定。`agents/code-header-generator.md`、`commands/`、`skills/`（`mcp-test`、`merge-specs`、`mermaid-diagram`、`xcode-build`、`xcode-test`） |
| `.doc_structure.yaml` | `docs/` をルール、`project/*/{spec,design,plan,mcp-guide}/` を仕様書として宣言 |

このプロジェクトはプラグインを同梱していません（`.claude-plugin/plugin.json` がありません）。`.claude/` はこのリポジトリ自身の AI 用設定です。

## 4. 用語集

<!-- bilingual-docs: allow-ja:start -->

| 日本語 | 英語表記 | 意味と使い方 |
| --- | --- | --- |
| ビルド不要 | build-free | ビルドが成功していなくても解析できること。SwiftSyntax を使うため。第一の設計原則 |
| 静的解析 | static analysis | コンパイルせずに SwiftSyntax で構文木を解析すること。各ツールのベースライン |
| メタツールモード | meta tool mode | 既定のモード（v0.6.3 以降）。`initialize_project`、`list_available_tools`、`get_tool_schema`、`execute_tool` だけを公開し、ほかは `execute_tool` 経由で呼ぶ |
| メタツール | meta tool | `list_available_tools`、`get_tool_schema`、`execute_tool` のいずれか。`Sources/Tools/Meta/` にある |
| レガシーモード | legacy mode | `SWIFT_SELENA_LEGACY=1` で選ぶモード。12 個のツールを直接公開する |
| MCPツール | MCP tool | `MCPTool` プロトコルに準拠するツールの実装（15 個のツール定義のうち 13 個。`InitializeProjectTool` と `ExecuteToolTool` は準拠しない） |
| 解析ツール | analysis tool | `execute_tool` 経由で呼ぶ 11 個のツール。`initialize_project` とメタツールは解析ツールではない |
| ハイブリッドアーキテクチャ | hybrid architecture | SwiftSyntax をベースラインとし、SourceKit-LSP をオプションの強化とする構成 |
| グレースフルデグレード | graceful degradation | LSP が使えない、または失敗したときに SwiftSyntax へフォールバックすること |
| LSP統合 | LSP integration | `LSPState` が有効にしたとき（プロジェクトルート直下に `.xcodeproj` がないとき）、対応ツールに SourceKit-LSP を使うこと。ビルドできるかは調べない |
| ProjectMemory | ProjectMemory | 解析結果の永続キャッシュ（`memory.json`）。識別子としてそのまま使う |
| クライアントID | client ID | `MCP_CLIENT_ID` の値。クライアントごとにキャッシュを分ける（未設定は `default`） |
| Visitor（訪問者） | visitor | `Sources/Selena/Visitors/` にある `SyntaxVisitor` のサブクラス。1 種類の情報を抽出する |
| コードヘッダー | Code Header | `[Code Header Format]` で始まる Swift ファイルの構造化ヘッダーコメント。形式は `docs/format/code_header_format.md` |
| Code Header DB | Code Header DB | Code Header を対象とする、計画中のデータベースとセマンティック検索（REQ-004、DES-006）。文書上の名前のまま使う |
| 要件定義書 | requirements document | `project/{feature}/spec/` のファイル。ID 接頭辞は `REQ-`。すべての文書より優先する |
| 設計書 | design document | `project/{feature}/design/` のファイル。ID は `DES-XXX`。何を作るかでなく、どう作るかを書く |
| 計画書 | plan document | `project/{feature}/plan/` のファイル。名前は `{feature}_plan.md` |
| Feature | feature | `project/` 直下の単位ディレクトリ（たとえば `main`） |
| 仕様書 | specification (spec) | 要件定義書と設計書をまとめて指す一般的な語。`.doc_structure.yaml` が索引化する |
| ルール文書 | rule document | `docs/` 配下のファイル（ルール、フォーマット、ワークフロー） |
| リリースタグ | release tag | `v` なしの `MAJOR.MINOR.PATCH` 形式の git tag。`main` の第 1 親ライン上に打つ |
| 機能登場版マーカー | feature-introduction marker | README の「v0.6.3 以降で利用可能」のような表記。`v` を付けてよい |
| Formula | Formula | Homebrew のレシピ `Formula/swift-selena.rb`。`tag:` を使い、`revision:` は書かない |
| bottle | bottle | tag の push 時に CI がビルドする、Homebrew のビルド済みバイナリ |

<!-- bilingual-docs: allow-ja:end -->

## 5. 表記の取り決め

- **文書 ID。** ID は元の接頭辞と番号のまま書き、訳しません: `REQ-001`、`DES-104`、`FR-006`、`NFR-001`、`UC-001`。節は「REQ-003 の 2.2 節」のように引用します。文書名も訳しません。
- **日本語のままの文書の見出し。** spec、design、plan の文書と `CHANGELOG.md` は日本語で書かれています。英語の文書がその見出しを引用するときは、日本語を引用符で囲んだまま残し、括弧で短い英語の説明を添えます（例: 「Swift-Selena 要件定義書」(Swift-Selena requirements)）。英語の文書では、用語集を除き、ほかの場所で日本語を引用しません。
- **コードブロック。** コード、コマンド、パス、フラグ、ツール名、識別子は訳しません。このプロジェクトではソースコードのコメントを日本語で書きます（`CLAUDE.md`）。英語の文書では、コードブロック内の文章のコメントを英語に訳し、コード自体は変えません。
- **ツール名とパラメータ名**（`search_code`、`output_mode`、`symbol_kinds`）はそのまま使います。
- **バージョン。** リリースのバージョンは `v` なしで書きます（`0.6.12`）。「v0.6.3 以降で利用可能」のような表記は `v` を付けてよいです（`CLAUDE.md`）。
- **用語の選び方。** 用語集の英語表記をどこでも使います。特に「meta tool mode」と「legacy mode」は区別し、`project/` の三種類の文書には「requirements document」「design document」「plan document」を使います。
- **リポジトリの言語。** AI との対話とソースコメントは日本語で書きます。ファイルも日本語で書きますが、すでに英語で書かれたファイル、またはユーザーが英語を指定したファイルは英語です（`CLAUDE.md`）。このリポジトリの英語ファイル（`README_en.md`、`DEVELOPMENT.md`）はすでにあり、そのまま残します。
- **ツール一覧。** 古い spec と design の文書からツール数や一覧を写さないでください。一覧は `ToolNames` と `MetaToolRegistry.swift` から書きます。
