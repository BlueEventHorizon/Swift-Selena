# Swift-Selena: Project Overview

This document is for people who join the development of Swift-Selena and for the AI that writes or fixes its documents. For installation and usage, see `README_en.md` (English) and `README.md` (Japanese). For the rules the development AI must follow, see `CLAUDE.md`. This survey describes the development branch after release 0.6.12: `AppConstants.version` in `Sources/Constants.swift` is still 0.6.12, while changes made after that tag (the cache format v6 and the Swift 6.1 requirement among them) are described as they are in the source, not as released.

## 1. Position

Swift-Selena is an MCP (Model Context Protocol) server, written as a Swift Package, that gives AI agents code analysis for Swift projects. It runs as a local process that clients start and talk to over stdio (JSON-RPC). Clients named in the README are Claude Code, Claude Desktop, Cursor, and Codex. It requires macOS 13.0 or later and a Swift 6.1 toolchain (Xcode 16.3) or later to build (`Package.swift`, `swift-tools-version: 6.1`, the lowest version that resolves the pinned dependencies: swift-nio 2.98.0 requires 6.1, and swift-log 1.12.0 declares 6.2 but ships a `Package@swift-6.1.swift` manifest for 6.1); the language mode stays Swift 5 (`swiftLanguageModes: [.v5]`). Verified on Swift 6.4. It is distributed through a Homebrew tap that is this repository itself (`Formula/swift-selena.rb`).

The problem it addresses, as stated in the overall requirements (`project/main/spec/REQ-001_Swift_Selena_Overall_Requirements.md`):

- Code under active development often does not build, and tools that need a successful build (SourceKit-LSP, Xcode) cannot analyze it.
- Source code should not leave the local machine.
- Results must be fast on large projects.

The same requirements compare it with Serena (a general-purpose, multi-language MCP server), SourceKit-LSP, and Xcode. Its stated distinct value is: no build needed, Swift-specific analysis (SwiftUI property wrappers, protocol conformances, extensions, tests), and MCP integration. It is read-only toward the analyzed project: it does not change the project's code and does not build it (REQ-001 section 7). It does write its own cache and logs under `~/.swift-selena/`.

## 2. Design intent and how it works

### Principles

The same four principles appear in REQ-001 (section 6.2) and in the development plan (`project/main/plan/main_plan.md`).

1. **Build-free analysis.** The baseline is static analysis with SwiftSyntax. It works when the syntax is valid, even if type checking fails.
2. **Local only.** No network communication; analysis results are stored under `~/.swift-selena/`.
3. **Staged enhancement.** SwiftSyntax is the baseline and SourceKit-LSP is an optional enhancement. When LSP is unavailable or fails, the tool falls back to SwiftSyntax (graceful degradation).
4. **Operational realism.** Maintenance-free and automatic updates (the wording of REQ-001; no further explanation is given in the documents).

### Request flow

```text
Client -> JSON-RPC over stdio -> SwiftMCPServer (MCP SDK)
       -> meta tool (execute_tool) -> a tool conforming to MCPTool
       -> analysis engine (SwiftSyntax / LSP / FileSearcher)
       -> ProjectMemory (cache) -> response
```

- **Tools.** There are 15 tool definitions: `initialize_project`, 11 analysis tools, and 3 meta tools. Tool names are defined in `ToolNames` in `Sources/Constants.swift` (12 names: `initialize_project` plus the 11 analysis tools) and in `MetaToolNames`; the registry that the meta tools read is `Sources/Tools/Meta/MetaToolRegistry.swift`. 13 of the 15 conform to the `MCPTool` protocol (`Sources/Tools/ToolProtocol.swift`). The two exceptions are `InitializeProjectTool`, which `SwiftMCPServer` dispatches directly, and `ExecuteToolTool`, whose `execute` takes an `LSPState` and dispatches to the analysis tools with a `switch`.
- **Meta tool mode (default, since v0.6.3).** The client sees only four tools: `initialize_project`, `list_available_tools`, `get_tool_schema`, and `execute_tool`. The 11 analysis tools are compiled into the binary like everything else; they are only hidden from the MCP tool list and reached through `execute_tool`, to keep context window usage low. **Legacy mode** (`SWIFT_SELENA_LEGACY=1`) exposes the 12 `ToolNames` tools directly.
- **Analysis engine.** `SwiftSyntaxAnalyzer` walks the syntax tree with SwiftSyntax visitors (symbols, imports, property wrappers, type conformances, extensions, XCTest, Swift Testing). `FileSearcher` searches the file system. `LSPClient` and `LSPState` handle SourceKit-LSP; the connection is made in the background after `initialize_project`. `LSPState` does not test whether the project builds: it disables LSP only when the project root contains a `.xcodeproj` (`Sources/Selena/LSP/LSPState.swift`).
- **Cache.** `ProjectMemory` (`Sources/Selena/Core/ProjectMemory.swift`) is the whole cache layer; it persists `memory.json` per client (`MCP_CLIENT_ID`) and per project (a hash of the project path) under `~/.swift-selena/clients/`. Invalidation is by file modification time. Each cache keeps its own per-file index (`fileIndex` for symbols, `importFileIndex` for imports, `typeFileIndex` for type conformances), recorded when that cache is written and checked when a single entry is read, so refreshing one cache never makes a stale entry of another look current. The bulk getters `getAllImports` and `getAllTypeConformances` return the cache as stored without that check. `getAllImports` has no caller in `Sources/`; the only caller of `getAllTypeConformances`, `getTypeHierarchy`, refreshes the type conformance cache first on every call: it drops entries of deleted files and re-parses only files that are new or changed since they were cached.

For the detailed design, see `DES-101` (architecture), `DES-102` (LSP integration), `DES-103` (tool implementation), and `DES-104` (enhancement of `search_code` and `find_symbol_definition`), all in `project/main/design/`. DES-101 and DES-103 describe the state at v0.5.3, DES-102 the LSP integration phase v0.5.1 to v0.5.5 (see "Documents of different ages" below).

### Priority of documents

The requirement documents under `project/{feature}/spec/` have the highest priority of all documents (`CLAUDE.md`, `docs/rules/base/project_rule.md`). A human decides; the AI drafts and changes requirements, designs, plans, and code (`project_rule.md`, section 4).

### Documents of different ages

The spec and design documents were written in stages, from v0.5.x to v0.6.x. Several of them still describe a state that no longer exists (for example 18 tools, `find_symbol_references`, `find_type_usages`, `read_symbol`). The documents themselves say that the current tool list is defined by `ToolNames` in `Sources/Constants.swift` and by `MetaToolRegistry.swift`; treat those two files as the source of truth for the tool list. Other signs of age: REQ-001 to REQ-004 and DES-101 to DES-103 carry the status "承認待ち" (awaiting approval) although later versions have been released; the index `project/main/spec/README.md` does not list REQ-004 and points to documents that do not exist (`DES-007` to `DES-009` among them); and several documents still cite REQ-005, which was merged into REQ-003 at v0.6.8 and deleted (DES-104 explains this). The Code Header DB (REQ-004, DES-006, and the tools `search_code_headers` and `get_code_header_stats`) is specified, but neither tool exists in `Sources/`.

### Release and versioning

The canonical version is `AppConstants.version`. Git tags have no `v` prefix. Release tags go on the first-parent line of `main`, and the Formula uses `tag:` only (no `revision:`). The authoritative procedure is in `CLAUDE.md`; `DEVELOPMENT.md` gives diagrams. CI checks consistency (`scripts/verify_version_consistency.sh`, `scripts/verify_release_tag.sh`) and builds bottles on a tag push. No workflow runs `swift build` or `swift test`; tests are run locally.

## 3. Structure

| Path | Role |
| --- | --- |
| `README.md`, `README_en.md` | Introduction for first-time users: Japanese and English. The repository's English README is currently `README_en.md` |
| `DEVELOPMENT.md`, `DEVELOPMENT.ja.md` | Development guide: build, test, add a tool, CI, release procedure |
| `CLAUDE.md` | Mandatory rules for the development AI. `AGENTS.md` is a symbolic link to it, and `GEMINI.md` only imports it |
| `CHANGELOG.md` | Release history (written in Japanese) |
| `Sources/` | The server. `SwiftMCPServer.swift` (entry point), `Constants.swift`, `Logging/`, `Selena/` (analysis engine: `Core/`, `LSP/`, `Visitors/` with 8 visitors, `DebugRunner.swift`), `Tools/` (`Project/`, `FileSystem/`, `Symbols/`, `SwiftUI/`, `Analysis/`, `Meta/`, `ToolProtocol.swift`, `ResultEncoder.swift`) |
| `Tests/` | Test targets and `Tests/Fixtures/` (sample code to analyze). Five targets are registered in `Package.swift` |
| `scripts/`, `makefile`, `Formula/`, `.github/workflows/` | Client registration, version and tag verification, bottle merging, the Homebrew Formula, and CI |
| `project/main/spec/` | Requirements `REQ-001` to `REQ-004`, and an index (`README.md`) |
| `project/main/design/` | Designs `DES-004`, `DES-005`, `DES-006`, `DES-101` to `DES-104` |
| `project/main/plan/` | Development plan (`main_plan.md`) |
| `project/main/mcp-guide/` | General notes on MCP server development and the MCP Swift SDK (not specific to this project) |
| `docs/rules/base/` | Development rules: project rule, coding rule, review criteria, principles of software development, rule for using agents and MCP |
| `docs/format/` | Formats of spec, design, plan, and Code Header |
| `docs/workflow/plan/` | Workflows for creating designs and plans |
| `.claude/` | AI tooling of this repository: `agents/code-header-generator.md`, `commands/`, `skills/` (`mcp-test`, `merge-specs`, `mermaid-diagram`, `xcode-build`, `xcode-test`) |
| `.doc_structure.yaml` | Declares `docs/` as rules and `project/*/{spec,design,plan,mcp-guide}/` as specifications |
| `.claude/.doc-advisor/toc/` | Generated search index over those documents, used by `/forge:query-db-rules` and `/forge:query-db-specs`. Committed; regenerate with `/forge:update-db-rules` / `/forge:update-db-specs`, never edit by hand |

The project does not ship a plugin (no `.claude-plugin/plugin.json`). The `.claude/` directory holds the repository's own AI tooling.

## 4. Glossary

<!-- bilingual-docs: allow-ja:start -->

| Japanese term | English rendering | Meaning and how it is used |
| --- | --- | --- |
| ビルド不要 | build-free | The analysis works without a successful build, because it uses SwiftSyntax. The first design principle |
| 静的解析 | static analysis | Analysis of the syntax tree with SwiftSyntax, without compiling. The baseline of the tools |
| メタツールモード | meta tool mode | Default mode (since v0.6.3). Only `initialize_project`, `list_available_tools`, `get_tool_schema`, and `execute_tool` are exposed; the others are called through `execute_tool` |
| メタツール | meta tool | One of `list_available_tools`, `get_tool_schema`, `execute_tool`; they live in `Sources/Tools/Meta/` |
| レガシーモード | legacy mode | Mode selected by `SWIFT_SELENA_LEGACY=1`; the twelve tools are exposed directly |
| MCPツール | MCP tool | A tool implementation that conforms to the `MCPTool` protocol (13 of the 15 tool definitions; `InitializeProjectTool` and `ExecuteToolTool` do not) |
| 解析ツール | analysis tool | One of the 11 tools called through `execute_tool`. `initialize_project` and the meta tools are not analysis tools |
| ハイブリッドアーキテクチャ | hybrid architecture | SwiftSyntax as the baseline plus SourceKit-LSP as an optional enhancement |
| グレースフルデグレード | graceful degradation | When LSP is unavailable or fails, the tool falls back to SwiftSyntax |
| LSP統合 | LSP integration | Use of SourceKit-LSP for supported tools when `LSPState` enables it (no `.xcodeproj` at the project root); it does not check whether the project builds |
| ProjectMemory | ProjectMemory | The persistent cache of analysis results (`memory.json`). Kept as the identifier |
| クライアントID | client ID | The value of `MCP_CLIENT_ID`; it separates cached data per client (`default` when unset) |
| Visitor（訪問者） | visitor | A `SyntaxVisitor` subclass in `Sources/Selena/Visitors/` that extracts one kind of information |
| コードヘッダー | Code Header | The structured header comment of a Swift file, starting with `[Code Header Format]`. Format in `docs/format/code_header_format.md` |
| Code Header DB | Code Header DB | Planned database and semantic search over Code Headers (REQ-004, DES-006). Kept as the name in the documents |
| 要件定義書 | requirements document | A file in `project/{feature}/spec/`, ID prefix `REQ-`. It has the highest priority of all documents |
| 設計書 | design document | A file in `project/{feature}/design/`, ID `DES-XXX`. It describes how to build, not what |
| 計画書 | plan document | A file in `project/{feature}/plan/`, named `{feature}_plan.md` |
| Feature | feature | A unit directory under `project/` (for example `main`) |
| 仕様書 | specification (spec) | General word for requirements and design documents together. Indexed by `.doc_structure.yaml` |
| ルール文書 | rule document | A file under `docs/` (rules, formats, workflows) |
| リリースタグ | release tag | Git tag `MAJOR.MINOR.PATCH` without a `v` prefix, placed on the first-parent line of `main` |
| 機能登場版マーカー | feature-introduction marker | A phrase such as "available since v0.6.3" in a README; it may keep the `v` |
| Formula | Formula | The Homebrew recipe `Formula/swift-selena.rb`; it uses `tag:` and no `revision:` |
| bottle | bottle | A prebuilt Homebrew binary built by CI when a tag is pushed |

<!-- bilingual-docs: allow-ja:end -->

## 5. Writing conventions

- **Document IDs.** Write IDs as they are, with the original prefix and number, and do not translate them: `REQ-001`, `DES-104`, `FR-006`, `NFR-001`, `UC-001`. Sections are cited as "REQ-003 section 2.2". Plain document names are not translated either.
- **Headings of documents that are still in Japanese.** The spec, design, and plan documents and `CHANGELOG.md` are written in Japanese. When an English document quotes one of their headings, keep the Japanese text in quotation marks and add a short English gloss in parentheses, for example "Swift-Selena 要件定義書" (Swift-Selena requirements). Do not quote Japanese anywhere else in English files, except in the glossary.
- **Code blocks.** Code, commands, paths, flags, tool names, and identifiers are never translated. Comments in source code are written in Japanese in this project (`CLAUDE.md`); in an English document, translate a prose comment inside a code block into English, and leave the code unchanged.
- **Tool and parameter names** (`search_code`, `output_mode`, `symbol_kinds`) are kept as they are.
- **Versions.** Write release versions without a `v` prefix (`0.6.12`). A phrase such as "available since v0.6.3" may keep the `v` (`CLAUDE.md`).
- **Term choice.** Use the English rendering in the glossary everywhere. In particular, keep "meta tool mode" and "legacy mode" distinct, and use "requirements document", "design document", and "plan document" for the three kinds of document in `project/`.
- **Language of the repository.** Interaction with the AI and source comments are in Japanese. Files are written in Japanese unless an existing file is in English or the user asks for English (`CLAUDE.md`). The English files in this repository (`README_en.md`, `DEVELOPMENT.md`) already exist and are kept as they are.
- **Tool lists.** Do not copy a tool count or list from the old spec and design documents. State the list from `ToolNames` and `MetaToolRegistry.swift`.
