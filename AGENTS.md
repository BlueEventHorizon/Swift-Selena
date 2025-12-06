# Repository Guidelines

## Project Structure & Module Organization
- `Sources/` hosts all Swift code, split by component (e.g., `Sources/Tools/` for each MCP tool, `Sources/LSP/` for LSPState & LSPClient, `Sources/Support/` for logging and shared helpers).
- `Tests/` mirrors the source layout; add new suites beside their production counterparts to keep fixtures close to the code they exercise.
- `docs/` contains requirements, design specs (DES-###), and operational notes; refer to the format guides under `docs/format/` before editing or adding documents.
- Utility assets include `register-selena-to-claude-code.sh` (release registration) and `register-selena-to-claude-code-debug.sh` (debug self‑registration); keep them in sync with README instructions.

## Build, Test, and Development Commands
- `swift build` – compile the executable target `Swift-Selena`; run before submitting changes to verify compiler health.
- `swift run Swift-Selena` – launch the MCP server locally; pair it with `claude mcp add … -- ./path/to/.build/debug/Swift-Selena` for manual tool tests.
- `swift test` – execute XCTest suites; required for every feature branch.
- `make connect_*` / `make disconnect_*` – helper targets in `makefile` for registering Gemini, Figma, or Serena MCP servers during integration testing.

## Coding Style & Naming Conventions
- Follow standard Swift style: 4‑space indentation, `UpperCamelCase` for types, `lowerCamelCase` for methods/properties, and `SCREAMING_SNAKE_CASE` for constants only when necessary.
- Keep tools small and isolate shared behavior behind protocols such as `MCPTool`; new tool files live under `Sources/Tools/<Category>/<ToolName>Tool.swift`.
- Every Swift file must carry the Code Header Format block (`docs/format/code_header_format.md`); regenerate headers via Claude before committing structural changes.
- Documentation uses the DES/REQ numbering rules in `docs/format/*.md`; maintain mermaid diagrams whenever diagrams already exist.

## Testing Guidelines
- Use XCTest for unit coverage and rely on the in‑process `DebugRunner` (enabled in DEBUG builds) to exercise LSP flows; keep deterministic test sequences when editing it.
- Name tests as `test<Behavior>` and mirror filenames, e.g., `Sources/Tools/Symbols/ListSymbolsTool.swift` → `Tests/ToolsTests/Symbols/ListSymbolsToolTests.swift`.
- Validate MCP behavior by invoking tools through Claude Code (e.g., `mcp__swift-selena-debug__initialize_project(project_path: "...")`); avoid shell re‑implementations of tool logic.

## Commit & Pull Request Guidelines
- Write commits in imperative, present tense (“Add LSP diagnostics guard”), referencing scope when useful; group formatting or documentation edits separately from logic changes.
- PRs must describe the problem, solution, and testing evidence (commands run, Claude MCP calls, screenshots/log excerpts if relevant); link to REQ/DES IDs when touching requirements or design files.
- Confirm `swift build`, `swift test`, and at least one MCP round‑trip via Claude before requesting review; note unsupported scenarios (e.g., Xcode‑only projects) if they affect the change.

## Communication Guidelines
- レビューやClaudeとのやり取りは日本語で行うこと。PR説明・質問・ログ共有も日本語で統一し、意思決定の経緯をそのまま会話ログ（docs/LATEST_CONVERSATION_HISTORY.md など）へ反映させる。

## MCP Registration & Debugging Tips
- Use `register-selena-to-claude-code-debug.sh` for local testing; it builds DEBUG artifacts, registers them under `swift-selena-debug`, and keeps production registration untouched.
- Tail `~/.swift-selena/logs/server.log` when debugging; the FileLogHandler mirrors stderr output without polluting MCP stdout. Always pair `swift run` sessions with `server.waitUntilCompleted()` semantics to avoid zombie processes.
