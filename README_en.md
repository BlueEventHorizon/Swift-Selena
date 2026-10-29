# Swift Selena - Swift Analyzer MCP Server with respect to Serena

<img width="400" src="selena.png">

**Swift Selena** is an MCP (Model Context Protocol) server that gives AI agents Swift code analysis capabilities. It works even when the code has build errors, and strongly supports SwiftUI app development. It runs with any MCP-capable client, including Claude Code, Claude Desktop, Cursor, and Codex.

[![Swift 6.1+](https://img.shields.io/badge/Swift-6.1+-orange.svg)](https://swift.org)
[![Platform macOS](https://img.shields.io/badge/platform-macOS%2013+-lightgrey.svg)](https://www.apple.com/macos/)
[![License MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[日本語版はこちら / Japanese version](README.md)

## Table of Contents

- [Key Features](#key-features)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Connecting MCP Clients](#connecting-mcp-clients)
- [Usage](#usage)
- [Provided Tools](#provided-tools)
- [Configuration, Data, and Logs](#configuration-data-and-logs)
- [Troubleshooting](#troubleshooting)
- [Advanced Configuration](#advanced-configuration)
- [Architecture](#architecture)
- [Contributing and License](#contributing-and-license)

## Key Features

- **Build-free**: Works even with build errors, thanks to SwiftSyntax-based static analysis
- **LSP integration**: Enhances supported tools with SourceKit-LSP when available; SwiftSyntax remains the fallback
- **Meta tool mode**: Reduces context window usage with dynamic tool loading (v0.6.3+)
- **Swift Testing support**: Detects both XCTest and Swift Testing (`@Test`, `@Suite`) test cases
- **SwiftUI support**: Automatically detects property wrappers (`@State`, `@Binding`, etc.)
- **Fast search**: Filesystem-based search stays fast on large projects
- **Smart caching**: Caches analysis results to speed up repeated queries
- **Multi-client**: Use Claude Code, Claude Desktop, Cursor, and Codex at the same time (data is separated per client)

## Quick Start

```bash
# 1. Install (finishes in seconds when a bottle is available)
brew tap blueeventhorizon/swift-selena https://github.com/BlueEventHorizon/Swift-Selena
brew install blueeventhorizon/swift-selena/swift-selena

# 2. Register with your client (example: Claude Code)
claude mcp add swift-selena -- swift-selena
```

3. Open a Swift project in your client and ask it to "analyze this project".

For Claude Desktop, Cursor, and Codex, see [Connecting MCP Clients](#connecting-mcp-clients).

## Installation

### Requirements

- macOS 13.0 or later
- An MCP-capable client ([Claude Code](https://docs.claude.com/claude-code) / [Claude Desktop](https://claude.ai/download) / [Cursor](https://cursor.com) / [Codex](https://developers.openai.com/codex), etc.)
- Only when building from source: Swift 6.1 (Xcode 16.3) or later

### Homebrew (Recommended)

This repository itself serves as the tap — no separate `homebrew-*` repository is needed.

```bash
brew tap blueeventhorizon/swift-selena https://github.com/BlueEventHorizon/Swift-Selena
brew install blueeventhorizon/swift-selena/swift-selena
# After tapping, the short form also works:
# brew install swift-selena
```

After installation, `swift-selena` is on your `PATH` (typically `$(brew --prefix)/bin/swift-selena`).

#### Install time

| Situation | Time | What happens |
| --- | --- | --- |
| Bottle available (Apple Silicon, macOS 15 / macOS 26) | Seconds | Downloads a prebuilt binary |
| No bottle (Intel Macs, unsupported OS versions, releases without a bottle) | Several to ten-plus minutes | Builds from source, compiling dependencies such as swift-syntax (about 3 minutes on Apple Silicon with Xcode 27.1) |

Requirements when building from source:

- Swift 6.1+ (Xcode 16.3+) on macOS 13.0+. Verified on macOS 26 / Xcode 27.1 (Swift 6.4)
- A Command Line Tools-only build is **unverified**. If it fails with only CLT installed, install full Xcode

> **About the `brew doctor` warning "You should download the Command Line Tools for Xcode xx"**
> Homebrew prints this when the Command Line Tools are older than the installed Xcode. `swift build` uses the toolchain that `xcode-select` points to, so this does not affect building Swift-Selena.

### Build from Source (Alternative)

If Homebrew is unavailable, build manually:

```bash
git clone https://github.com/BlueEventHorizon/Swift-Selena.git
cd Swift-Selena
swift build -c release -Xswiftc -Osize
# Artifact: .build/release/Swift-Selena
```

In the registration steps below, replace `swift-selena` with `$(pwd)/.build/release/Swift-Selena`. For `make` commands, local development registration, and the release procedure, see [DEVELOPMENT.md](DEVELOPMENT.md).

## Connecting MCP Clients

Every client launches `swift-selena` as a **stdio** MCP server.

| Client | How to configure | Config file |
| --- | --- | --- |
| [Claude Code](#claude-code) | `claude mcp add` | `~/.claude.json` / `.mcp.json` |
| [Claude Desktop](#claude-desktop) | Edit JSON | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| [Cursor](#cursor) | Edit JSON | `~/.cursor/mcp.json` / `.cursor/mcp.json` |
| [Codex (CLI / IDE extension)](#codex) | `codex mcp add` or edit TOML | `~/.codex/config.toml` / `.codex/config.toml` |

### Common notes

- **GUI apps (Claude Desktop, Cursor, the Codex IDE extension) may not inherit your shell `PATH`.** Using an absolute path in the configuration is the safest. Find it with:

  ```bash
  echo "$(brew --prefix)/bin/swift-selena"
  # e.g. Apple Silicon → /opt/homebrew/bin/swift-selena / Intel → /usr/local/bin/swift-selena
  ```

- **Do not write `$(brew --prefix)` inside JSON or TOML.** It is not shell-expanded; paste the absolute path printed by the command above.
- **`MCP_CLIENT_ID` separates data per client.** Clients that use the same value share one analysis cache. See [Data location](#data-location).

The examples below assume Homebrew on Apple Silicon (`/opt/homebrew`).

### Claude Code

If the binary is on your `PATH`, no absolute path is needed. Pick a scope:

| Scope | Command | Applies to |
| --- | --- | --- |
| `local` (default) | `claude mcp add swift-selena -- swift-selena` | This project only, just you |
| `project` | `claude mcp add -s project swift-selena -- swift-selena` | This project, shared with the team via `.mcp.json` |
| `user` | `claude mcp add -s user swift-selena -- swift-selena` | All of your projects |

> **`project` scope note:** `.mcp.json` is committed to the repository and shared with your team. Because the registered `command` is `swift-selena` (resolved via `PATH`), every teammate must have `swift-selena` on their `PATH` (for example via this Homebrew formula).

### Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "swift-selena": {
      "command": "/opt/homebrew/bin/swift-selena",
      "env": { "MCP_CLIENT_ID": "claude-desktop" }
    }
  }
}
```

Restart Claude Desktop afterwards.

### Cursor

Edit `.cursor/mcp.json` for a single project, or `~/.cursor/mcp.json` for all projects:

```json
{
  "mcpServers": {
    "swift-selena": {
      "type": "stdio",
      "command": "/opt/homebrew/bin/swift-selena",
      "env": { "MCP_CLIENT_ID": "cursor" }
    }
  }
}
```

- After saving, check in Cursor's **Customize** sidebar that `swift-selena` is enabled. If its tools appear under `Available Tools` in chat, it is connected
- If it fails to connect, open the Output panel (`Cmd+Shift+U`) and select **MCP Logs** to see the error
- If you commit `.cursor/mcp.json`, make sure the absolute `command` path is the same on every teammate's machine

### Codex

The Codex CLI, IDE extension, and desktop app share the same configuration.

**Register with a command:**

```bash
codex mcp add swift-selena --env MCP_CLIENT_ID=codex -- "$(brew --prefix)/bin/swift-selena"
```

The shell expands `$(brew --prefix)` before the command runs, so an absolute path is what gets registered.

**Or edit the config file:** append to `~/.codex/config.toml` (per-project: `.codex/config.toml`, effective only for trusted projects):

```toml
[mcp_servers.swift-selena]
command = "/opt/homebrew/bin/swift-selena"

[mcp_servers.swift-selena.env]
MCP_CLIENT_ID = "codex"
```

- To verify, run `codex mcp list`, or type `/mcp` in Codex
- In the IDE extension you can also use the gear menu → **MCP servers** → **Add server** → **STDIO**. Then run **Restart extension**

## Usage

### Basic flow

1. **Initialize the project**: Ask your client to "analyze this Swift project"; `initialize_project` runs automatically
2. **Search and analyze code**: "Find the ViewModels" → `find_files` searches `*ViewModel.swift`. "Which files use `@State`?" → `list_property_wrappers` detects them
3. **Inspect code structure**: "Show the type hierarchy of ViewController" → `get_type_hierarchy` shows the inheritance

### Examples

#### Check SwiftUI property wrappers

```
You: Which property wrappers does ContentView.swift use?

AI: runs list_property_wrappers
Result:
[@State] counter: Int (line 12)
[@ObservedObject] viewModel: ViewModel (line 13)
[@EnvironmentObject] appState: AppState (line 14)
```

#### Find a specific function

```
You: Where is the function fetchData?

AI: runs find_symbol_definition
Result:
[Function] fetchData
  File: /path/to/NetworkManager.swift
  Line: 45
```

#### Check protocol conformances

```
You: Which protocols does ViewController conform to?

AI: runs list_protocol_conformances
Result:
[Class] ViewController (line 25)
  Inherits from: UIViewController
  Conforms to: UITableViewDelegate, UITableViewDataSource
```

#### Search production Swift files only

```json
{
  "pattern": "URLSession\\.shared",
  "output_mode": "file_list",
  "include_patterns": ["Sources/**/*.swift"],
  "exclude_patterns": ["*Tests*"],
  "limit": 100
}
```

(Example parameters for `search_code`.)

#### Narrow symbol definitions by kind

```json
{
  "symbol_name": "Button",
  "symbol_kinds": ["struct", "class"]
}
```

(Example parameters for `find_symbol_definition`. The result includes a Scope line and a structured JSON block.)

## Provided Tools

### Meta tool mode (v0.6.3+)

Swift-Selena uses **meta tool mode**: only the following 4 tools are exposed to the client. The actual analysis tools are loaded dynamically on demand, which keeps context window usage low.

| Exposed tool | Role |
| --- | --- |
| `initialize_project` | Initializes the project (always run first) |
| `list_available_tools` | Lists the available analysis tools and their descriptions |
| `get_tool_schema` | Returns the JSON schema of a specific tool |
| `execute_tool` | Runs an analysis tool by name |

### Analysis tools (via `execute_tool`)

| Category | Tool | Summary |
| --- | --- | --- |
| File search | `find_files` | Find files by wildcard pattern (e.g. `*ViewModel.swift`) |
| | `search_code` | Search code by regex. Supports `output_mode`, `limit`, `include_patterns`, `exclude_patterns` |
| | `search_files_without_pattern` | Find files that do not match a pattern (like `grep -L`). Supports `include_patterns`, `exclude_patterns` |
| Symbol analysis | `list_symbols` | List symbols such as classes, structs, and functions |
| | `find_symbol_definition` | Find a symbol definition across the project. Supports `symbol_kinds` and scope information |
| SwiftUI analysis | `list_property_wrappers` | Detect SwiftUI property wrappers (`@State`, `@Binding`, etc.) |
| | `list_protocol_conformances` | Analyze protocol conformances and inheritance (`UITableViewDelegate`, `ObservableObject`, etc.) |
| | `list_extensions` | Analyze extensions (extended type, protocol conformances, members) |
| Code analysis | `analyze_imports` | Analyze import dependencies across the project (module usage statistics, cached) |
| | `get_type_hierarchy` | Get a type's inheritance hierarchy (superclass, subclasses, conforming types, cached) |
| | `find_test_cases` | Detect XCTest and Swift Testing (`@Test`, `@Suite`) test cases |

### Tool specification notes

- `search_code`'s `output_mode` is `match_detail` (default), `file_list`, or `count_only`
- `search_code`'s `limit` is 1–10,000. Values above 10,000 are clamped to the internal maximum and the result says so
- `search_code` and `search_files_without_pattern` use `include_patterns` / `exclude_patterns`. The old `file_pattern` was intentionally removed and is ignored if passed
- `find_symbol_definition`'s `symbol_kinds` accepts `struct`, `class`, `enum`, `protocol`, `actor`, `function`, `variable`, `typealias`, and `extension`
- `search_code` and `find_symbol_definition` append a `--- structured ---` JSON block to the end of their human-readable text output
- LSP enhancement is best-effort. Xcode project directories containing `.xcodeproj` currently disable LSP, and SwiftSyntax analysis is used instead

## Configuration, Data, and Logs

### Data location

The analysis cache is stored under `~/.swift-selena/`:

```
~/.swift-selena/
├── logs/
│   └── server.log                # log
└── clients/
    ├── default/                  # MCP_CLIENT_ID unset (e.g. Claude Code)
    │   └── projects/
    │       └── YourProject-abc12345/
    │           └── memory.json
    ├── claude-desktop/           # MCP_CLIENT_ID=claude-desktop
    ├── cursor/                   # MCP_CLIENT_ID=cursor
    └── codex/                    # MCP_CLIENT_ID=codex
```

- The same project is identified by the SHA256 hash of its path; different projects are separated automatically
- Clients with different `MCP_CLIENT_ID` values get separate data automatically (`default` when unset)

> **Note:** Opening the same project at the same time from clients that share one `MCP_CLIENT_ID` (e.g. several Claude Code windows) can cause write conflicts on the memory file. When working on one project from several windows, give each a different `MCP_CLIENT_ID`.

### Logs (v0.5.3+)

Debug logs go to `~/.swift-selena/logs/server.log`.

```bash
# Watch in real time
tail -f ~/.swift-selena/logs/server.log
```

You can see server startup, tool execution, LSP connection status (success / failure), and errors with diagnostics.

```
[17:29:24] ℹ️ [info] Starting Swift MCP Server...
[17:29:50] ℹ️ [info] Tool called: initialize_project
[17:29:50] ℹ️ [info] Attempting LSP connection...
[17:29:51] ℹ️ [info] ✅ LSP connected successfully
```

## Troubleshooting

### The MCP server does not start

Check that the binary starts and prints the startup banner:

```bash
swift-selena
# OK if "Starting Swift MCP Server..." appears. Exit with Ctrl+C
```

If you built from source, run `.build/release/Swift-Selena` instead.

### Tools are missing or the client cannot connect

1. Restart the client (for the Codex IDE extension, **Restart extension**)
2. Check that the config file path and the absolute `command` path are correct
3. Check the client's logs

| Client | How to check |
| --- | --- |
| Claude Code | `claude mcp list` |
| Claude Desktop | `tail -f ~/Library/Logs/Claude/mcp*.log` |
| Cursor | Output panel (`Cmd+Shift+U`) → **MCP Logs** |
| Codex | `codex mcp list` / `/mcp` |

The server's own log is at `~/.swift-selena/logs/server.log`.

### `brew install` is slow

Without a bottle, the install builds from source and takes several to ten-plus minutes. See [Install time](#install-time).

### Clear the old cache

```bash
rm -rf ~/.swift-selena/
```

It is rebuilt the next time `initialize_project` runs.

## Advanced Configuration

### Legacy mode (expose all tools directly)

By default, **meta tool mode** (v0.6.3+) is used. To expose the 12 tools directly without the meta tools, set the environment variable `SWIFT_SELENA_LEGACY=1`.

| Client | Setting |
| --- | --- |
| Claude Code | `claude mcp add swift-selena -e SWIFT_SELENA_LEGACY=1 -- swift-selena` |
| Claude Desktop, Cursor | Add `"SWIFT_SELENA_LEGACY": "1"` to `env` |
| Codex | `codex mcp add swift-selena --env SWIFT_SELENA_LEGACY=1 -- swift-selena`, or add `SWIFT_SELENA_LEGACY = "1"` under `[mcp_servers.swift-selena.env]` |

Claude Desktop example:

```json
{
  "mcpServers": {
    "swift-selena": {
      "command": "/opt/homebrew/bin/swift-selena",
      "env": {
        "MCP_CLIENT_ID": "claude-desktop",
        "SWIFT_SELENA_LEGACY": "1"
      }
    }
  }
}
```

The 12 tools exposed directly in legacy mode:
`initialize_project`, `find_files`, `search_code`, `search_files_without_pattern`, `list_symbols`, `find_symbol_definition`, `list_property_wrappers`, `list_protocol_conformances`, `list_extensions`, `analyze_imports`, `get_type_hierarchy`, `find_test_cases`

## Architecture

### Core components

- **FileSearcher**: Fast filesystem-based search
- **SwiftSyntaxAnalyzer**: Symbol extraction through AST analysis
- **ProjectMemory**: Persistence and cache management of analysis results

### Tech stack

- **[MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)** (0.12.0) - MCP protocol implementation
- **[SwiftSyntax](https://github.com/apple/swift-syntax)** (602.0.0) - Syntax parsing
- **CryptoKit** - Hashing of project paths
- **swift-log** (via the MCP Swift SDK) - Logging

## Contributing and License

Issues and pull requests are welcome. For building, testing, adding tools, CI, and the release procedure (version bump + Homebrew Formula, with diagrams), see the [Development Guide (DEVELOPMENT.md)](DEVELOPMENT.md).

MIT License - see [LICENSE](LICENSE) for details.

## References

- [Model Context Protocol](https://modelcontextprotocol.io/) - MCP protocol specification
- [SwiftSyntax](https://github.com/apple/swift-syntax) - Swift syntax parsing library
- [Anthropic](https://www.anthropic.com/) - Claude AI
