# CLAUDE.md

Swift-Selena = MCP Server for Swift code analysis (Swift Package)

## AI Interaction Language [MANDATORY]

**All interaction must be conducted in Japanese**
- Technical terms and English words may be used as they are
- Source code comments are also written in Japanese
- Files are also written in Japanese. However, when the file being modified is already written in English, or when the user specifies otherwise, write in English

## Important Constraints [MANDATORY]

- **NEVER modify Xcode project files** (`*.xcodeproj/`) without explicit permission
  - Note: files are registered folder-based, so no change is needed when adding files
- **NEVER modify Info.plist or XCConfig files** without explicit permission
- **Requirements documents (project/{feature}/spec/) have the highest priority** (over all other documents)
- **Report document inconsistencies immediately**: when you find an inconsistency or contradiction in a document under `rules/`, `specs/`, or `.claude/`, stop the work and report it to the user as the top priority
- **Use existing code** before creating new ones (Sources/Tools/, Sources/Selena/)
- **Referring to existing code is mandatory**: before writing new code, search for existing similar implementations and use them as reference
- **"Created by" in file headers**: use the value of git config user.name
- **Document search at the start of work**: for work that requires reading documents, identify the relevant documents with `/forge:query-db-rules` and `/forge:query-db-specs`, read them, and only then start the work
- **Automatic DB index update**: run `/forge:update-db-rules` after adding, changing, or deleting a document under docs/, and `/forge:update-db-specs` after adding, changing, deleting, or moving a document under project/{feature}/spec/ or project/{feature}/design/ (the scope of the index is defined by `.doc_structure.yaml`)
- **No direct editing of DB indexes**: do not edit the index files under `.claude/doc-advisor/` and `.claude/doc-db/` directly; update them with `/forge:update-db-rules` / `/forge:update-db-specs`
- **Consider using the Swift-Selena MCP**: when the Swift-Selena MCP is connected, judge from the MCP's description whether it is efficient and effective for code analysis work, and consider using it (no experiment is needed; decide from the MCP's description)
- **Consider using the Xcode MCP**: when the Xcode MCP is connected, only in situations the Skills (`/xcode:build` / `/xcode:test`) do not cover, judge from the MCP's description whether it is effective, and consider using it
- **Tests that require an MCP server restart need a request to the user**: an end-to-end test that requires restarting an MCP server (such as the Swift-Selena MCP), for example checking behavior after a code change or checking behavior with the cache discarded, **must not be run by the AI on its own judgment; always ask the user to restart first, then run it**
  - The AI cannot restart the MCP server, which is a separate process
  - When a restart is needed, ask the user and state the restart procedure explicitly (whether the binary must be rebuilt, which caches must be deleted, which behavior you want to check)
  - When verification can be substituted by unit tests, prefer that, and decide whether E2E verification is needed
- **Version notation convention** (established in Issue #38; the canonical reference for the whole project):
  - **canonical (source of truth)**: `AppConstants.version` in `Sources/Constants.swift` (for example `"0.6.10"`). Updated with `/forge:update-version`
  - **git tag**: `MAJOR.MINOR.PATCH` format (**no `v` prefix**, for example `0.6.10`). Consistent with the 16 existing tags
  - **CHANGELOG.md header (new entries)**: `## VERSION - YYYY-MM-DD` format (**no `v` prefix**, for example `## 0.6.10 - 2026-05-27`). Past entries (`## v0.6.X` format) are a historical record and are not fixed retroactively
  - **`.version-config.yaml`**: `tag_format` is `"{version}"` (no `v`)
  - **Exception**: **feature-introduction markers** in the README files, such as "feature X is available since v0.6.3", may keep the `v` (an independent contextual notation)
  - **Verification**: `scripts/verify_version_consistency.sh` checks that the canonical version (`Sources/Constants.swift`), the first CHANGELOG entry, and `tag_format` / `version_file` / `version_path` in `.version-config.yaml` agree. The CI workflow `.github/workflows/version_check.yml` verifies this automatically on every PR
  - **The Formula is outside the verify script**: `tag:` in `Formula/swift-selena.rb` matches the version string, but it is not part of the mandatory checks of `verify_version_consistency.sh`. Formula consistency is ensured by `scripts/verify_release_tag.sh` described below (verified after the tag is fixed) and by a real `brew install` verification
- **Release tags are created on the mainline of main (the first-parent line)**: a release tag in `{version}` format (**no `v` prefix**) must always be created on **the head commit of main immediately after the version bump is merged into main**
  - Put the tag on main's merge commit (or on the head commit after a fast-forward). This places the tag on main's mainline
  - **Do not write `revision:` in the Formula** (`tag:` only). The tag commit contains the Formula itself, so its SHA can never be written into the Formula (circular). Without `revision:`, the "tag and revision mismatch" (Issue #38) cannot occur
  - Do not run `git tag` ahead of time on a working branch such as `develop` (merge into main, check out main, then tag)
  - Before creating the tag, confirm with `git branch --show-current` that you are on main, and with `git status -sb` that it matches `origin/main` (already pushed)
  - Delete a tag created on the wrong commit or branch with `git tag -d <tag> && git push <remote> :<tag>` and recreate it on the correct commit
- **Release procedure (Formula bundled, single merge)**: bundle the version bump and the Formula `tag:` update in the same PR, and consolidate the merge into main into **one** merge. Carry it out in the following 3 phases
  - **Phase 1 — bump PR (working branch)**:
    1. Run `/forge:update-version <target> <patch|minor|major>` (updates `Sources/Constants.swift` and inserts a new entry into the CHANGELOG) and commit
    2. Update `tag:` in `Formula/swift-selena.rb` to `{version}` (do not write `revision:`) and commit
    3. Verify locally with `scripts/verify_version_consistency.sh` (version strings agree) and `brew style Formula/swift-selena.rb` (Formula syntax)
    4. Push, then create and merge the PR (into a working branch such as `develop`)
  - **Phase 2 — merge into main + tag (on main)**:
    5. Merge the changes of `develop` into `main` and push (the merge method does not matter; squash / rebase are fine because nothing depends on the SHA)
    6. Check out `main`, confirm with `git branch --show-current`, then `git tag {version}` (head of main), then `git push <remote> {version}`. **Tag promptly after merging into main** (to minimize the period in which the Formula's `tag:` points to a tag that does not exist yet)
    7. Verify with `scripts/verify_release_tag.sh {version}` that "the tag is on main's first-parent line", "the Constants version at the tag commit == {version}", "the Formula `tag:` == {version}", and "the Formula has no `revision:`" (`exit 1` on inconsistency). CI `release_tag_check.yml` also verifies this automatically when the tag is pushed
    8. After the tap is updated, verify a real install with `brew install --build-from-source` (`serverInfo.version == {version}`)
  - **Phase 3 — bottle update (optional, after the tag push)**: the tag push makes `bottle.yml` build bottles and attach them to the Release (CI does not push to the repo)
    9. After confirming that bottles are attached to the Release, create a working branch from `develop`, run `scripts/merge_bottles.sh {version}`, and commit the changed Formula
    10. Merge develop into main as usual (the Formula's `tag:` is not changed; the bottle update commit lands after the tag)
- **On the drift of existing release artifacts (documented limitation)**: this convention applies only to changes committed from HEAD onward. Even if `AppConstants.version` and similar values in the source of an existing release tag (for example `0.6.10`) have drifted, this convention does not fix them retroactively (to keep the git history intact). If the `serverInfo.version` of an existing release binary installed through Homebrew does not match the canonical version, accept it as "known historical drift"; full consistency is first reached at the next release

## Development Language and Frameworks

Use the technologies available on the platforms and versions defined in Package.swift.
- **macOS**: 13.0+
- **Swift**: 6.1 (`swift-tools-version`; the language mode is Swift 5 via `swiftLanguageModes: [.v5]`)
- **Type**: Swift Package (MCP Server)

## Critical Documentation Structure

```text
project/
└── {feature}/           # One directory per feature (currently only main)
    ├── spec/            # Requirements documents (document ID: REQ-XXX; item IDs in the body: FR-/NFR-/UC-)
    ├── design/          # Design documents (document ID: DES-XXX)
    ├── plan/            # Development plan ({feature}_plan.md)
    └── mcp-guide/       # General notes on MCP server development and the MCP Swift SDK

docs/
├── rules/base/          # Basic rules (project_rule, coding_rule, review_criteria, etc.)
├── workflow/plan/       # Planning-phase workflows (design_workflow, planning_workflow)
└── format/              # Document format specifications (spec_format, plan_format, design_format, code_header_format)

.doc_structure.yaml      # Declares docs/ as rules and project/*/{spec,design,plan,mcp-guide}/ as specifications
.claude/.doc-advisor/    # Search index used by /forge:query-db-rules / /forge:query-db-specs (do not edit directly)
```

## Architecture Deep Dive

### Swift-Selena MCP Server Architecture

```
Sources/
├── SwiftMCPServer.swift     # MCP server entry point
├── Constants.swift          # Constant definitions and environment variable keys
├── Logging/                 # Logging
├── Selena/                  # Core analysis engine
│   ├── Core/                # Core features
│   │   ├── FileSearcher.swift       # Fast file-system-based search
│   │   ├── SwiftSyntaxAnalyzer.swift# AST analysis (symbols, types, imports, etc.)
│   │   └── ProjectMemory.swift      # Cache management of analysis results (persistence, invalidation by modification time)
│   ├── LSP/                 # SourceKit-LSP integration (disabled when a .xcodeproj exists)
│   │   ├── LSPClient.swift
│   │   └── LSPState.swift
│   ├── Visitors/            # SwiftSyntax visitors (8 kinds)
│   │   ├── SymbolVisitor.swift
│   │   ├── SymbolVisitorV2.swift
│   │   ├── ImportVisitor.swift
│   │   ├── PropertyWrapperVisitor.swift
│   │   ├── TypeConformanceVisitor.swift
│   │   ├── ExtensionVisitor.swift
│   │   ├── XCTestVisitor.swift
│   │   └── SwiftTestingVisitor.swift
│   └── DebugRunner.swift    # Automatic run for debugging (DEBUG only)
└── Tools/                   # MCP tool implementations
    ├── Analysis/            # Code analysis tools (3 tools)
    ├── FileSystem/          # File operation tools (3 tools)
    ├── Meta/                # Meta tools (3 tools + MetaToolRegistry)
    ├── Project/             # Project management tools (1 tool)
    ├── SwiftUI/             # SwiftUI analysis tools (3 tools)
    ├── Symbols/             # Symbol analysis tools (2 tools)
    ├── ToolProtocol.swift   # Common tool protocol
    └── ResultEncoder.swift  # Encoding of tool results
```

### MCP Server Request Flow

```
Claude/Client
    ↓ JSON-RPC over stdio
SwiftMCPServer (MCP SDK)
    ↓ tool call
Tool implementation (conforms to MCPTool)
    ↓ analysis
Selena analysis engine
    ↓ result
ProjectMemory (cache)
    ↓ response
Claude/Client
```

**Key principles**:
- New tools conform to the MCPTool protocol (existing exceptions: `InitializeProjectTool` is called directly by SwiftMCPServer, and `ExecuteToolTool` has its own signature that takes an `LSPState`)
- Static analysis with SwiftSyntax (build-free)
- Semantic analysis through LSP integration (when the project can be built)

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

### Mandatory Requirements
- **NEVER modify Package.swift** without explicit permission
- **Japanese comments required** in source code (all code comments are in Japanese)
- **Requirements documents (project/{feature}/spec/**/*.md) have the highest priority** (over all other documents)
- **Use existing utilities** before creating new ones (Sources/Tools/, Sources/Selena/)
- **Always update documentation** when making specification changes
- **"Created by" in file headers**: use the value of git config user.name (not the generative AI)
- **Update the specification index**: after adding, changing, deleting, or moving a file under project/{feature}/spec/ or project/{feature}/design/, run `/forge:update-db-specs` (same as "Automatic DB index update" above)

### MCP Server Implementation Principles
- **MCPTool conformance**: new tools implement the `MCPTool` protocol (defined in `Sources/Tools/ToolProtocol.swift`)
- **Static analysis first**: SwiftSyntax-based analysis is the baseline; LSP is used as a supplement
- **Use the cache**: analysis results are cached in ProjectMemory
- **Error handling**: tool execution errors are returned properly as MCP responses

## Use of MCP [MANDATORY]

### Swift-Selena MCP (recommended, fast)
**Situations for use**:
- **Before implementing**: search for existing similar implementations to prevent duplication
- **Refactoring**: search every use of a type or symbol to prevent missed changes
- **Architecture check**: detect layer violations, check protocol conformance
- **Code understanding**: read efficiently symbol by symbol, grasp the project structure
- **Knowledge accumulation**: save and search important specifications and designs as memos

**Alternative when not connected**: the Grep/Glob tools (slower, less precise)

### Gemini MCP
- Checking how to use OS frameworks
- Investigating how to use external APIs
- Web search (Google search)


## Critical Implementation Constraints

### Sources/Tools/ - Tool Implementation Constraints
- **MCPTool conformance**: new tools conform to the `MCPTool` protocol defined in `Sources/Tools/ToolProtocol.swift` (`InitializeProjectTool` and `ExecuteToolTool` are existing exceptions)
- **Category placement**:
  - `Analysis/` - code analysis (imports, type hierarchy, etc.)
  - `FileSystem/` - file operations (find_files, search_code, etc.)
  - `Symbols/` - symbol analysis (list_symbols, find_symbol_definition, etc.)
  - `SwiftUI/` - SwiftUI-specific analysis (property wrappers, protocol conformances, etc.)
  - `Meta/` - meta tools (list_available_tools, get_tool_schema, execute_tool) + MetaToolRegistry (the registry)
  - `Project/` - project management (initialize_project, etc.)
- **Error handling**: analysis errors are included in the MCP response as proper error messages

### Sources/Selena/ - Core Analysis Engine Constraints
- **Core/FileSearcher**: fast file-system-based search
- **Core/SwiftSyntaxAnalyzer**: static analysis with SwiftSyntax (build-free), using the visitors under Visitors/
- **Core/ProjectMemory**: cache management of analysis results (persisted to `memory.json`, invalidated by file modification time). This file is the whole cache layer
- **LSP/**: SourceKit-LSP integration through LSPClient and LSPState (disabled when a `.xcodeproj` exists directly under the project root; it does not check whether the project can be built)
- **Visitors/**: SwiftSyntax SyntaxVisitor subclasses (symbol, import, type analysis, etc.)

### Code Header Format [MANDATORY]
- **ALWAYS add/update Code Header Format** when creating/modifying Swift files
- **Required marker**: `[Code Header Format]` at the beginning of header comment
- **Required sections**:
  - `目的` (Purpose): the role of this file (2-4 items, one line each, concise)
  - `主要機能` (Main features): the features it provides (2-5 items, one line each, concise)
  - `含まれる型` (Contained types): the types defined in this file (only when present)
  - `関連型` (Related types): the external types it depends on (only when present)
- **Format spec**: `docs/format/code_header_format.md`
- **Auto-generate command**: `/create-code-headers --changed` (git-changed files only)
- **Verification**: Check for `[Code Header Format]` marker in all modified Swift files before task completion

## important-instruction-reminders

Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.
