English | [日本語](ja/CHANGELOG.ja.md)

# Release History

Release history of Swift-Selena.

---

## 0.6.12 - 2026-10-29

### Homebrew bottle distribution

- **feat**: Added CI (`.github/workflows/bottle.yml`) that builds bottles for Apple Silicon (macOS 15 / macOS 26) on a tag push and attaches them to the GitHub Release. The CI does not push to the repository
- **feat**: Added `scripts/merge_bottles.sh`, which writes the bottle JSON from the Release into the Formula (run it on a working branch; the change reaches `main` through the usual develop → main flow)
- **docs**: README.md / README_en.md now describe how long a source build takes, what a bottle is, the verified environment (macOS 26 / Xcode 27.1), and that the `brew doctor` warning about the Command Line Tools has no effect on the build
- **docs**: Added Phase 3 (bottle merge) to the release procedure in CLAUDE.md
- **change**: Release tags are now placed on the first-parent line of `main`. The Formula no longer has a `revision:` and resolves the source by `tag:` alone (the tag commit contains the Formula itself, so its SHA cannot be written into the Formula; this removes that circular dependency). `scripts/verify_release_tag.sh`, `release_tag_check.yml`, CLAUDE.md, and CONTRIBUTING were updated to the new procedure

## 0.6.11 - 2026-05-31

### Issue #37: Homebrew install

- **feat**: Added a Homebrew Formula (`Formula/swift-selena.rb`). The repository itself is the tap and the Formula builds from source, so `brew install` is a one-step install (commit `4bb3f68`)
  - `caveats` gives the MCP registration steps for Claude Code and Claude Desktop separately, and `test` verifies the MCP `initialize` handshake (`serverInfo.name`)
- **docs**: Added a Homebrew (recommended) section to README.md / README.ja.md, alongside the source-build steps (commits `4bb3f68`, `7f111db`)
- **docs**: Updated the install flow in design document DES-101 section 10.2 to the Homebrew sequence (commit `4bb3f68`)

### Issue #38: Unified version notation

- **chore**: Unified the version notation across the project. The canonical version is `AppConstants.version` in `Sources/Constants.swift`; git tags and CHANGELOG headers no longer carry a `v` prefix (commit `366da88`)
- **feat**: Added the version consistency script `scripts/verify_version_consistency.sh`; the CI workflow `version_check.yml` checks on every PR that the canonical version, the first CHANGELOG entry, and `.version-config.yaml` agree (commit `366da88`)
- **chore**: Documented the release procedure in CLAUDE.md as a three-phase flow (version bump → tag on main → Formula bump), and removed the quotes from `version_path` in `.version-config.yaml` (commit `39e7485`)

### Development infrastructure

- **ci**: Added `close-issues-on-develop.yaml`, which closes the corresponding Issues automatically on a merge into develop (commit `5ef3554`)
- **chore**: Removed the doc-advisor search index (`.claude/doc-advisor/index/{rules,specs}/*`) from git (commit `df17fcc`)

### Notes

- This release is about Homebrew install support (#37) and unified version notation (#38). The public tool API and the analysis features of the Swift-Selena MCP server itself are unchanged
- The canonical version (`Sources/Constants.swift`) was updated from 0.6.10 to 0.6.11

## 0.6.10 - 2026-05-27

### Development infrastructure

- **feat**: Added the `.claude/skills/xcode-build` and `.claude/skills/xcode-test` skills (commit `4b57a94`)
- **fix**: Fixed defects in the xcode skills (commit `ce0a40b`)
- **fix**: Fixed forge-db related defects (commit `74cd007`)
- **chore**: Removed the unneeded `.claude/skills/skill-creator` files and `.claude/doc-db/index/rules/*` (commit `35e43c5`)

### Notes

- This release changes only the development skills and document indexes under `.claude/`. The features and public tool API of the Swift-Selena MCP server itself are unchanged
- This entry was back-filled after the actual release, as part of Issue #38 (unified version notation). It was reconstructed from `git log 0.6.9..0.6.10` and `git diff --name-status 0.6.9..0.6.10` as primary sources, because the release notes body of GitHub Release v0.6.10 was empty
- Starting with this entry, headings use the form without a `v` prefix (`## VERSION - YYYY-MM-DD`). Older entries (`## v0.6.X`) are kept unchanged as a historical record

## v0.6.9 - 2026-05-17

### Issue #34: Unified parameter API for `search_files_without_pattern`

- **breaking**: Removed the `file_pattern` parameter of `search_files_without_pattern`
  - Replaced by `include_patterns` / `exclude_patterns` (arrays of globs, up to 20 entries each), the same API as `search_code`
  - If `file_pattern` is still passed, it is ignored as an unknown parameter per DES-104 section 5.1 (no error)
- **feat**: `FileSearcher.searchFilesWithoutPattern` now takes `includePatterns` / `excludePatterns`
  - It reuses the `shouldSearchFile` / `compiledGlobRegexes` helpers shared with `searchCode`, so both apply the same rule: include patterns are OR-ed, and exclude patterns take precedence
- **feat**: `SearchFilesWithoutPatternTool` validates the regular expression syntax, glob syntax, and array sizes in the tool layer before searching
  - Errors are returned in the unified DES-104 section 8.1 format through `ResultEncoder.buildErrorResponse(cause:suggestion:)`
- **chore**: Removed the shared constant `ParameterKeys.filePattern` from `Sources/Constants.swift` entirely
- **test**: Added 5 cases for `search_files_without_pattern` to `BackwardCompatibilityTests`
  - `file_pattern` is ignored (confirms the breaking change)
  - filtering with `include_patterns`
  - `exclude_patterns` take precedence
  - error response when an array exceeds the size limit
  - error response for an invalid regular expression
- **docs**: Updated DES-104 to v2.1 (reflects Issue #34 and states that section 5.1 applies to both tools)
- **docs**: Corrected the `search_code` input fields in `REQ-003_Core_Features_Requirements.md` to `include_patterns` / `exclude_patterns` (a retroactive fix for an omission in 0.6.8)
- **docs**: Updated the test parameters of the `mcp-test` skill (`search_code` / `search_files_without_pattern`) from `file_pattern` to `include_patterns`

---

## v0.6.8 - 2026-05-16

### REQ-005 / DES-104: Search and symbol tool extensions

- **feat**: Extended `search_code` / `find_symbol_definition` / `list_symbols` according to REQ-005 / DES-104
  - Added `SymbolInfoV2` and `listSymbolsWithScope`; three fields, `parent_scope` / `extension_target` / `module_name`, distinguish the scope of a symbol
  - `SymbolKindMapper` is the single place that maps the 9 lowercase snake_case kind values (struct/class/enum/protocol/actor/function/variable/typealias/extension) to the display kinds
  - When `symbol_kinds` is not given, results are stably sorted in a priority order (Class/Struct/Enum/Protocol/Actor first, then the rest)
  - `CapabilityRegistry` registers the capabilities of each tool; `list_available_tools` returns them
  - Files that fail to parse are collected as `skipped_files` in the structured result (DES-104 section 8.4)
- **feat**: Added `SymbolVisitorV2` as an independent implementation (a scope stack kept symmetric through visit/visitPost)
  - An extension itself is registered as a symbol of kind `Extension`
  - Nested types, types inside extensions, and root types are fully distinguished through `parent_scope` / `extension_target`
- **feat**: `module_name` resolution now understands the `path:` attribute
  - `.target(...)`, `.executableTarget(...)`, and similar declarations in `Package.swift` are extracted by tracking parenthesis depth, and the target root is computed from `name` and `path`
  - Longest-prefix matching gives a unique answer when there are several targets
  - Layouts where the target name differs from the directory name, such as `path: "Sources"`, are supported (Swift-Selena itself is one)
  - If target parsing fails, it falls back to the old `Sources/{firstName}/` pattern

### Breaking changes

- **breaking**: Removed the `file_pattern` parameter of `search_code` (REQ-005 sections 4.3 / 4.6)
  - Replaced by `include_patterns` / `exclude_patterns`

### Cache schema

- **fix**: `cacheVersion` bumped in steps from v3 to v4 to v5
  - v4: `SymbolInfo` gained `parentScope` / `extensionTarget` / `moduleName`
  - v5: corrects the history of fields having been added within the same cacheVersion; v4 caches from the three-field period are discarded and rebuilt
- **fix**: On a version mismatch or decode failure the cache recovers to empty memory and sets the `cache_warning` flag (DES-104 section 8.2)

### Tests

- **test**: Added `SymbolVisitorV2Tests` (scope distinction / push-pop symmetry / module name resolution, 6 cases)
- **test**: Added `SearchCodeToolTests` / `FindSymbolDefinitionToolTests`
- **test**: `BackwardCompatibilityTests` verifies the v3 → latest and v4 → v5 migrations

### Documents

- **docs**: Added REQ-005 (requirements for the search and symbol tool extensions) and DES-104 (design document)
- **docs**: Added the improve plan document and set up traceability for REQ-005 / DES-104
- **docs**: Corrected `ToolProtocol` to `MCPTool` in CLAUDE.md
- **docs**: Made it a rule that tests requiring an MCP server restart must be requested from the user

---

## v0.6.7 - 2026-04-21

### Build error fixes

- **fix**: Updated swift-sdk from 0.10.2 to 0.12.0 (fixes the `#SendingRisksDataRace` error in `NetworkTransport.swift` caused by the stricter `StrictConcurrency` checking of the Swift 6.3.1 compiler)
- **fix**: Updated the pattern match in `DebugRunner.swift` to the new API (the `.text` enum case now has three associated values, `(text:annotations:_meta:)`, so the pattern became `.text(let text, _, _)`)

---

## v0.6.6 - 2026-04-02

### Refactoring and quality

- LSPClient is now an actor, which removes the race condition on messageId
- Code review follow-ups: LSP hang fix, synchronous initialization fix, URI escaping fix, parameter parsing fix, thread safety improvements
- SearchFilesWithoutPatternTool no longer walks directories twice
- InitializeProjectTool: removed dead code and fixed the `String(describing:)` usage
- Errors are no longer swallowed (a failed `save()` is written to the log as a warning)
- Removed dead code in the `Cache/` directory
- Consolidated `scripts/` and unified the Makefile

### Documents and settings

- Merged REQ-005 into REQ-003 (absorbing the 0.6.5 requirements) and deleted REQ-005
- Updated doc-advisor and removed the old doc-advisor
- Refactored docs
- Set up `settings.json`; `settings.local.json` is no longer tracked by git
- Updated `.gitignore`

---

## v0.6.3 - 2025/12/15〜2026/03/11

### Meta tool mode, Swift version support, script consolidation

**New feature: meta tool mode (2025-12-15):**
- **MetaToolRegistry**: all analysis tools are managed dynamically through a registry
- **list_available_tools**: lists the available tools with their descriptions
- **get_tool_schema**: returns the JSON schema of one tool
- **execute_tool**: runs a tool by name, with the arguments passed as JSON
- **SWIFT_SELENA_LEGACY=1**: the previous mode, which exposes every tool directly, is kept as a fallback (legacy mode)
- The tools exposed to Claude are reduced to four, minimizing context window consumption

**Swift version support (2025-12-15):**
- **SymbolVisitor**: handles the syntax of newer Swift versions

**Swift Testing (2025-12-17):**
- **SwiftTestingVisitor** (new): a dedicated visitor detects the `@Test` / `@Suite` macros
- **FindTestCasesTool**: analyzes XCTest and Swift Testing together

**Bug fix: protocol recognition (2026-01-06):**
- **TypeConformanceVisitor** reworked: much better at telling protocols from classes
  - Fixed `list_protocol_conformances` reporting a protocol as a class
  - Added dedicated detection of protocol declarations
  - Cleaned up the storage format in ProjectMemory

**Other (2026-01-06):**
- Added the MIT LICENSE file

**Script consolidation and Makefile (2026-03-11):**
- New `scripts/` directory holding every shell script
  - `register-release.sh`, `unregister-release.sh`, `register-debug.sh`, `register-desktop.sh`
- Removed the `.sh` files at the repository root (`register-selena-to-claude-code.sh` and others)
- The Makefile is the single entry point; the scripts no longer need to be run directly

**Makefile registration commands:**

| Command | Target | Description |
|---------|--------|-------------|
| `make register-release` | Claude Code | Register the RELEASE build (path entered interactively) |
| `make unregister-release` | Claude Code | Unregister the RELEASE build (path entered interactively) |
| `make register-debug` | Claude Code | Build and register the DEBUG build |
| `make unregister-debug` | Claude Code | Unregister the DEBUG build |
| `make register-desktop` | Claude Desktop | Register with Claude Desktop |
| `make unregister-desktop` | Claude Desktop | Unregister from Claude Desktop |

**Total tools:** 15 (4 meta tools + 11 analysis tools)

---

## v0.6.1 - 2025/12/06

### Build and registration refactoring

**Makefile introduced:**
- **make build**: DEBUG build
- **make build-release**: RELEASE build
- **make register-debug**: register the DEBUG build with this project
- **make register-desktop**: register with Claude Desktop
- **make install-client-makefile TARGET=/path**: distribute the client Makefile

**File layout changes:**
- `register-*.sh` moved to `Tools/Scripts/`
- The client `Makefile` moved to `Tools/Client/`
- A new `Makefile` manages build and registration in one place

**Bug fixes:**
- **DebugRunner path**: the hard-coded path is now detected dynamically
  - Added the `detectProjectPath()` method

**Total tools:** 15 (unchanged)

---

## v0.5.5 - 2025/10/27

### LSP stabilization, MCP foundation fixes, new tool

**New feature:**
- **search_files_without_pattern**: the equivalent of `grep -L`, a search for what is missing
  - Finds files without a Code Header
  - Finds files without an import statement
  - Shows statistics (files checked, files without the pattern, percentage)

**Important bug fixes (6):**
1. **Multi-line regular expressions**: added `.anchorsMatchLines`, so `^import` matches on every line
2. **Zombie process**: `server.waitUntilCompleted()` ends cleanly on EOF; the infinite loop was removed
3. **Production environment contamination**: the development build is registered under the separate name `swift-selena-debug`, fully separating it from the production build
4. **LSP asynchronous notifications mixed into responses**: Content-Length is handled exactly, and publishDiagnostics is skipped
5. **LSPState limited to one project**: a Dictionary now manages several projects
6. **initialize_project in the background**: waits synchronously and returns after the LSP connection completes

**find_symbol_references removed:**
- Findings: works on Swift Packages; always returns 0 results on Xcode projects
- Cause: SourceKit-LSP Issue #730 (Xcode projects not supported)
- Decision: removed (about 270 lines); find_type_usages is recommended as the alternative
- Reason: a configuration that works for every project type takes priority

**Documents:**
- CLAUDE.md: added the language setting, failure patterns and countermeasures, a checklist, and document update rules
- PLAN.md: reflects the 0.5.5 implementation
- LATEST_CONVERSATION_HISTORY.md: 0.5.5 summary
- MCP_LSP_LEARNINGS.md: added important lessons

**Lessons:**
- MCP specification: `server.waitUntilCompleted()` is required; no infinite loop is needed
- LSP limitation: reference search does not work on Xcode projects; documentSymbol / typeHierarchy do
- Complete separation of development and production builds: registering under a different name prevents contamination of the production environment

**Total tools:** 18 (reduced by the removal of find_symbol_references)

**Details**: see docs/LATEST_CONVERSATION_HISTORY.md and docs/MCP_LSP_LEARNINGS.md

---

## v0.5.4 - 2025/10/26

### LSP type information in list_symbols and get_type_hierarchy

**LSPClient extensions:**
- **documentSymbol()**: implements the textDocument/documentSymbol API
- **typeHierarchy()**: implements the textDocument/prepareTypeHierarchy API
- Added the LSPDocumentSymbol and LSPTypeHierarchy structs

**list_symbols:**
- Added the executeWithLSP() method
- LSP version: shows type information (for example `[Method] save: func save() throws`)
- SwiftSyntax version: as before (fallback)
- symbolKindToString() converts the LSP SymbolKind

**get_type_hierarchy:**
- Added the executeWithLSP() method
- LSP version: adds Type Detail (for example `Type Detail: class ProjectMemory`)
- SwiftSyntax version: as before (fallback)
- Graceful degradation fully implemented

**Completed:**
- LSPClient extensions (documentSymbol, typeHierarchy)
- Hierarchical structures (recursive processing of children)
- Excluded directories (263 files, exact match)
- Files with no imports
- Log timestamps in JST
- Graceful degradation complete

**Test results:**
- ContactB project: every tool verified with exact matches
- find_symbol_references: works
- Graceful degradation complete

**Total tools:**
- Without a build: 17
- With a build: 18
- Enhanced tools: 2 (list_symbols, get_type_hierarchy)

**Details**: see the v0.5.4 section of docs/CONVERSATION_HISTORY.md

---

## v0.5.3 - 2025/10/24

### LSP stabilization and debugging features

**LSP fixes (find_symbol_references fully working):**
- **initialized notification**: added, for LSP protocol compliance
- **textDocument/didOpen**: implemented, so files are announced to the LSP
- **initialize response discarded**: clears the buffer
- **SIGPIPE**: `signal(SIGPIPE, SIG_IGN)`
- **Content-Length**: computed from the actual JSON length
- **Error handling**: process state checks and try-catch

**Debugging features:**
- **FileLogHandler**: writes logs to a file (`~/.swift-selena/logs/server.log`)
- **DebugRunner**: in-process automatic test runner (`#if DEBUG`, works with the Xcode debugger)
- **LSPState diagnostics**: added the getStatus() method

**Verification:**
- find_symbol_references: no crash in 5 consecutive runs
- References to LSPState: 3 found
- References to ProjectMemory: 34 found
- FindSymbolReferencesTool: 3 found

**Technical details:**
- Full LSP protocol compliance (initialize → initialized → didOpen → requests)
- Opened files are cached (openedFiles)
- publishDiagnostics notifications are handled correctly
- Detailed logging of response parsing

**Total tools:** 18 (unchanged; stability improved)

**Documents:**
- README.md / README.ja.md: added how to monitor the logs
- docs/tool_design/DES-008: DebugRunner design document

**Details**: see docs/tool_design/DES-008_DebugRunner_Design.md

---

## v0.5.2 - 2025/10/21

### LSP features

**New tool:**
- **find_symbol_references**: symbol reference search (LSP)
  - Accurate reference search based on type information
  - Uses the textDocument/references request
  - Available only when the project builds (dynamic tool list)
  - When LSP is unavailable, find_type_usages and search_code are suggested instead

**Implementation:**
- Added the lspState parameter to FindSymbolReferencesTool.execute()
- SwiftMCPServer passes lspState to it
- A wrapper keeps conformance to the MCPTool protocol
- Conversion between 0-indexed and 1-indexed positions

**Total tools:**
- Without a build: 17 (SwiftSyntax only)
- With a build: 18 (+find_symbol_references)

**Design decisions:**
- The list_symbols and get_type_hierarchy enhancements are deferred to 0.5.3
- Reason: integrating LSP documentSymbol needs more implementation time
- 0.5.2 concentrates on the basic LSP feature (reference search)

**Removed:**
- get_tool_usage_stats (deferred to 0.8.0)
  - Backward compatibility problems
  - Needs a design review (manage it outside ProjectMemory)

**Commits:**
- 7cfd60c: complete FindSymbolReferencesTool
- cfdd1eb: add: FindSymbolReferencesTool

**Details**: see the v0.5.2 section of docs/tool_design/PLAN.md

---

## v0.5.1 - 2025/10/21

### LSP foundation

**New components:**
- LSPState actor: manages the LSP connection state
- LSPClient: SourceKit-LSP communication (JSON-RPC over stdin/stdout)
- Dynamic tool list (the tools change with the LSP state)

**Features:**
- Background LSP connection (at initialize_project, non-blocking)
- LSP features offered only when the project builds (from 0.5.2)
- Graceful degradation (SwiftSyntax keeps working when LSP fails)

**Design decisions:**
- BuildChecker removed (attempting the LSP connection directly is enough)
- The same simple approach as Serena

---

### Tool reduction and cleanup

**Removed tools (5):**
- read_file: fully replaced by Claude's standard Read
- read_lines: fully replaced by Claude's standard Read
- read_function_body: replaced by read_symbol
- list_directory: fully replaced by Claude's Bash (`ls`)
- get_project_stats: low value

**Why:**

**Performance:**
- read_file: Swift-Selena = Claude Read (no difference)
- read_lines: limited context efficiency (the whole file ends up being read anyway)
- list_directory: same as the `ls` command (no difference)

**Accuracy:**
- All give the same results (file system operations)

**Replaceability:**
- read_file, read_lines, list_directory: 100% replaced by Claude's standard features
- read_function_body: replaced by read_symbol(symbol_path: "Class/method")
- get_project_stats: search_notes is enough

**Conclusion:**
- Remove the overlap with Claude's standard features
- Swift-Selena specializes in Swift analysis
- Less maintenance

**Total tools**: 22 → **17**

---

### Change of direction

**Rethinking the LSP tool additions:**

**Previous plan:**
- Add 5 new LSP tools (find_symbol_references, get_symbol_info, and others)
- Total tools: 22 → 27

**New direction:**
- Enhance existing tools with LSP (add as few new tools as possible)
- list_symbols: type information when LSP is used
- get_type_hierarchy: also includes find_overrides information when LSP is used

**Only new addition:**
- find_symbol_references (no existing feature covers it)

**Final tool count**: 17 → 18 (+1 only)

**Details**: see the design documents in docs/tool_design/

---

## v0.5.0 - 2025/10/13

### New features

**5 new tools (22 in total):**

1. **set_analysis_mode**: switches the analysis mode
   - SwiftUI / Architecture / Testing / Refactoring / General modes
   - Gives tool usage guidance per mode
   - Modeled on Serena's mode feature

2. **read_symbol**: reads one symbol
   - Returns only the requested symbol instead of the whole file
   - Much better context efficiency on large files (5000+ lines)

3. **list_directory**: lists a directory
   - Lists files and directories
   - Recursive option

4. **read_file**: general file reading
   - Reads files of any kind
   - Configuration files, JSON files, and so on

5. **think_about_analysis**: a thinking prompt
   - A prompt that encourages checking the progress of an analysis
   - Improves analysis quality

### Improvements

- Total tools: 17 → 22
- The mode feature guides the best tool usage for each task
- Better support for large projects

### Technology stack

- SwiftSyntax 602.0.0
- MCP Swift SDK 0.10.2
- Swift 5.9+

---

## v0.4.2 - 2025/10/06

### Features

- **17 tools**
  - Project management: 1
  - File search: 2
  - SwiftSyntax analysis: 9
  - Efficient reading: 2
  - Project notes: 3

- **SwiftUI-specific features**
  - Property wrapper analysis (@State, @Binding, and others)
  - Protocol conformance and inheritance analysis
  - Extension analysis

- **Cache system (0.4.0)**
  - Per-file cache
  - Automatic garbage collection
  - Automatic invalidation on file changes

- **Multiple clients**
  - Data separated by MCP_CLIENT_ID
  - Claude Code and Claude Desktop at the same time

### Technology stack

- SwiftSyntax 602.0.0
- MCP Swift SDK 0.10.2
- CryptoKit (project path hash)
- swift-log

### Architecture

- Works without a build (SwiftSyntax-based)
- Runs entirely locally
- Stdio transport

---

## v0.4.0 - 2025/10/04

### Main changes

- Per-file cache system (`Cache/` directory)
- CacheManager, FileCacheEntry, and CacheGarbageCollector implemented
- Automatic garbage collection (every hour OR every 100 requests)
- Automatic cache invalidation on file changes

### Breaking changes

- Cache format changed (memory.json → cache.json)
- Existing caches must be rebuilt

---

## v0.3.0 - 2025/10/03

### Main changes

- Basic SwiftSyntax analysis
- SwiftUI-specific features
  - Property wrapper analysis
  - Protocol conformance analysis
  - Extension analysis
- File and code search (with excluded directories)
- Import dependency analysis
- Type inheritance hierarchy analysis
- XCTest case detection
- Tracking of type usages (find_type_usages)
- Codebase refactoring (file splitting)
- Multiple clients (project path hash)

**Tools**: 17

---

## Future plans

For the detailed development plan, see:

**Hybrid Architecture Plan** (the document is no longer in the repository)
- 0.5.0 to 0.5.4: LSP integration roadmap
- Detailed design of the hybrid architecture

---

**Last Updated**: 2026-03-11
