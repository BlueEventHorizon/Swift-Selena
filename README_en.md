# Swift Selena - Swift Analyzer MCP Server with respect to Serena

<img width="400" src="selena.png">

**Swift Selena** is an MCP (Model Context Protocol) server that provides Swift code analysis capabilities to Claude AI. It works even with build errors and strongly supports SwiftUI app development.

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform macOS](https://img.shields.io/badge/platform-macOS%2013+-lightgrey.svg)](https://www.apple.com/macos/)
[![License MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[日本語版はこちら / Japanese version](README.md)

## Key Features

- **Build-Free**: Works even with build errors through SwiftSyntax-based static analysis
- **LSP Integration**: Enhances supported tools with SourceKit-LSP when available; SwiftSyntax remains the fallback
- **Meta Tool Mode**: Reduces context window usage with dynamic tool loading (v0.6.3+)
- **Swift Testing Support**: Detects both XCTest and Swift Testing (@Test, @Suite) test cases
- **SwiftUI Support**: Automatically detects Property Wrappers (@State, @Binding, etc.)
- **Fast Search**: Filesystem-based search for fast performance even on large projects
- **Smart Caching**: Caches analysis results for fast repeated queries
- **Multi-Client Support**: Use with Claude Code and Claude Desktop simultaneously

## Provided Tools

### Meta Tool Mode (v0.6.3+)

Swift-Selena uses a **Meta Tool Mode** that exposes only 4 tools to Claude, reducing context window usage. The actual analysis tools are loaded dynamically on demand.

**Exposed Tools:**
- **`initialize_project`** - Initialize a project (must be called first)
- **`list_available_tools`** - List all available analysis tools with descriptions
- **`get_tool_schema`** - Get the JSON schema for a specific tool
- **`execute_tool`** - Execute any analysis tool by name

### Available Analysis Tools (via execute_tool)

#### File Search
- **`find_files`** - Search files by wildcard pattern (e.g., `*ViewModel.swift`)
- **`search_code`** - Search code content using regex; supports `output_mode`, `limit`, `include_patterns`, and `exclude_patterns`
- **`search_files_without_pattern`** - Search files WITHOUT a pattern (grep -L equivalent); supports `include_patterns` and `exclude_patterns`

#### Symbol Analysis
- **`list_symbols`** - List all symbols (Class, Struct, Function, etc.)
- **`find_symbol_definition`** - Find symbol definitions across the project; supports `symbol_kinds` and scope information

#### SwiftUI Analysis
- **`list_property_wrappers`** - Detect SwiftUI Property Wrappers (@State, @Binding, etc.)
- **`list_protocol_conformances`** - Analyze protocol conformances and inheritance (UITableViewDelegate, ObservableObject, etc.)
- **`list_extensions`** - Analyze extensions (extended type, protocol conformance, members)

#### Code Analysis
- **`analyze_imports`** - Analyze import dependencies across the project (module usage statistics, cached)
- **`get_type_hierarchy`** - Get type inheritance hierarchy (superclass, subclasses, conforming types, cached)
- **`find_test_cases`** - Detect XCTest and Swift Testing (@Test, @Suite) test cases

### Current Tool Notes

- `search_code` output modes are `match_detail` (default), `file_list`, and `count_only`
- `search_code` accepts `limit` from 1 to 10,000; values above 10,000 are clamped and reported
- `search_code` and `search_files_without_pattern` use `include_patterns` / `exclude_patterns`; the old `file_pattern` parameter is intentionally removed and ignored if passed
- `find_symbol_definition` accepts `symbol_kinds`: `struct`, `class`, `enum`, `protocol`, `actor`, `function`, `variable`, `typealias`, `extension`
- `search_code` and `find_symbol_definition` append a `--- structured ---` JSON block after the human-readable text output
- LSP enhancement is best-effort. Xcode project directories containing `.xcodeproj` currently disable LSP, and SwiftSyntax analysis is used instead

## Installation

### Requirements

- macOS 13.0 or later
- Swift 5.9 or later
- [Claude Desktop](https://claude.ai/download) or [Claude Code](https://docs.claude.com/claude-code)

### Homebrew (Recommended)

**Tap and install** (the explicit-URL `brew tap` form lets this repository serve as a tap directly — no separate `homebrew-*` repository is required):

```bash
brew tap blueeventhorizon/swift-selena https://github.com/BlueEventHorizon/Swift-Selena
brew install blueeventhorizon/swift-selena/swift-selena
# After tap, the short form also works:
# brew install swift-selena
```

After `brew install`, the `swift-selena` binary is on your `PATH` (typically `$(brew --prefix)/bin/swift-selena`).

> **Swift toolchain requirement:** Building requires Swift 5.9+ on macOS 13.0+. Verified with full Xcode 15+ providing Swift 5.9+. The Command Line Tools-only path is plausible but **was not verified at the time of this release**; if you have only CLT installed and `brew install` fails, install Xcode 15+ as a workaround.

#### Register to Claude Code

The binary is on `PATH`, so no absolute path is required. Pick a scope:

| Scope | Command | Availability |
| --- | --- | --- |
| `local` (default) | `claude mcp add swift-selena -- swift-selena` | This project only, just you |
| `project` | `claude mcp add -s project swift-selena -- swift-selena` | This project, shared with your team via `.mcp.json` |
| `user` | `claude mcp add -s user swift-selena -- swift-selena` | All of your projects |

```bash
# This project only (local, default)
claude mcp add swift-selena -- swift-selena
```

> **`project` scope note:** `-s project` commits `.mcp.json` to the repository and shares it with your team. Because the registered `command` is `swift-selena` (resolved via `PATH`), every teammate must have `swift-selena` installed on their `PATH` (e.g. via this Homebrew formula); otherwise it won't start for them.

#### Register to Claude Desktop

Claude Desktop is launched from the GUI and does **not** always inherit the interactive shell `PATH`. Use the absolute path returned by `brew --prefix`:

```bash
# Find the install prefix (typical: /opt/homebrew on Apple Silicon, /usr/local on Intel)
brew --prefix
```

Edit `~/Library/Application Support/Claude/claude_desktop_config.json` and paste the **actual** path (not a shell expression — JSON is not shell-expanded):

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

> ⚠️ Do **not** write `$(brew --prefix)` literally inside the JSON — JSON is not shell-expanded. Run `brew --prefix` first and paste the resulting absolute path.

Restart Claude Desktop after editing.

### Build from source (alternative)

If Homebrew is unavailable (e.g. a restricted environment), build and register manually:

```bash
git clone https://github.com/BlueEventHorizon/Swift-Selena.git
cd Swift-Selena
swift build -c release -Xswiftc -Osize
# Artifact: .build/release/Swift-Selena
```

Register the built binary with Claude Code:

```bash
claude mcp add -s user swift-selena -- "$(pwd)/.build/release/Swift-Selena"
```

> For all `make` commands, local development registration, and the release procedure, see **[CONTRIBUTING.md](CONTRIBUTING.md)**.

## Debugging & Logging

### Log File Monitoring (v0.5.3+)

Swift-Selena outputs logs to a file for debugging and troubleshooting:

**Log file location:**
```
~/.swift-selena/logs/server.log
```

**Monitor logs in real-time:**
```bash
tail -f ~/.swift-selena/logs/server.log
```

**What you can see:**
- Server startup messages
- Tool execution logs
- LSP connection status (success/failure)
- Error messages and diagnostics

**Example log output:**
```
[17:29:24] ℹ️ [info] Starting Swift MCP Server...
[17:29:50] ℹ️ [info] Tool called: initialize_project
[17:29:50] ℹ️ [info] Attempting LSP connection...
[17:29:51] ℹ️ [info] ✅ LSP connected successfully
```

**Tip:** Keep `tail -f` running in a separate terminal while using Swift-Selena for real-time debugging.

## Usage

### Basic Workflow

1. **Initialize project**
```
Ask Claude: "Analyze this Swift project"
→ initialize_project is automatically executed
```

2. **Search and analyze code**
```
"Find ViewModels"
→ find_files searches for *ViewModel.swift

"Which files use @State?"
→ list_property_wrappers detects them
```

3. **Analyze code structure**
```
"Show me the type hierarchy for ViewController"
→ get_type_hierarchy displays inheritance
```

### Practical Examples

#### Check SwiftUI Property Wrappers
```
You: Tell me what Property Wrappers are used in ContentView.swift

Claude: Executes list_property_wrappers
Result:
[@State] counter: Int (line 12)
[@ObservedObject] viewModel: ViewModel (line 13)
[@EnvironmentObject] appState: AppState (line 14)
```

#### Find a specific function
```
You: Find where the fetchData function is defined

Claude: Executes find_symbol_definition
Result:
[Function] fetchData
  File: /path/to/NetworkManager.swift
  Line: 45
```

#### Check protocol conformance
```
You: Tell me what protocols ViewController conforms to

Claude: Executes list_protocol_conformances
Result:
[Class] ViewController (line 25)
  Inherits from: UIViewController
  Conforms to: UITableViewDelegate, UITableViewDataSource
```

#### Search for error handling across the project
```
You: Find all do-catch blocks

Claude: Executes search_code (regex: do\s*\{)
Result: Found 15 do-catch blocks
```

#### Search only production Swift files
```
Claude: Executes search_code
Params:
{
  "pattern": "URLSession\\.shared",
  "output_mode": "file_list",
  "include_patterns": ["Sources/**/*.swift"],
  "exclude_patterns": ["*Tests*"],
  "limit": 100
}
```

#### Narrow symbol definitions by kind
```
Claude: Executes find_symbol_definition
Params:
{
  "symbol_name": "Button",
  "symbol_kinds": ["struct", "class"]
}
Result includes Scope lines and a structured JSON block.
```

## Data Storage

Analysis cache is stored in the following directory:

```
~/.swift-selena/
└── clients/
    ├── default/              # Claude Code (default)
    │   └── projects/
    │       └── YourProject-abc12345/
    │           └── memory.json
    └── claude-desktop/       # Claude Desktop
        └── projects/
            └── YourProject-abc12345/
                └── memory.json
```

- Projects are identified by SHA256 hash of project path
- Different projects are automatically separated
- Claude Code (`default`) and Claude Desktop (`claude-desktop`) data is automatically separated by `MCP_CLIENT_ID`

**Note**: When the same `MCP_CLIENT_ID` (e.g., multiple Claude Code windows) opens the same project simultaneously, memory file write conflicts may occur. If working on the same project in multiple windows, set different `MCP_CLIENT_ID` values.

## Troubleshooting

### MCP server won't start

Check that the binary runs and prints its startup banner:

```bash
# Homebrew install
swift-selena
# "Starting Swift MCP Server..." should appear; press Ctrl+C to exit
```

If you built from source, run `.build/release/Swift-Selena` instead (see [CONTRIBUTING.md](CONTRIBUTING.md)).

### Tools not found

1. Restart Claude Desktop/Code
2. Verify config file paths are correct
3. Check logs:
```bash
tail -f ~/Library/Logs/Claude/mcp*.log
```

### Clear old cache

```bash
rm -rf ~/.swift-selena/
```

Will be rebuilt on next `initialize_project` execution.

## Advanced Configuration

### Legacy Mode (All Tools Exposed)

By default, Swift-Selena uses **Meta Tool Mode** (v0.6.3+). If you prefer to have 12 tools exposed directly without meta tool indirection, set the `SWIFT_SELENA_LEGACY=1` environment variable:

#### Claude Desktop
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

#### Claude Code
```bash
claude mcp add swift-selena -e SWIFT_SELENA_LEGACY=1 -- swift-selena
```

In legacy mode, the following 12 tools are exposed directly:
`initialize_project`, `find_files`, `search_code`, `search_files_without_pattern`, `list_symbols`, `find_symbol_definition`, `list_property_wrappers`, `list_protocol_conformances`, `list_extensions`, `analyze_imports`, `get_type_hierarchy`, `find_test_cases`

## Architecture

### Core Components

- **FileSearcher**: Fast filesystem-based search
- **SwiftSyntaxAnalyzer**: Symbol extraction via AST analysis
- **ProjectMemory**: Persists analysis results and manages cache

### Technology Stack

- **[MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)** (0.12.0) - MCP protocol implementation
- **[SwiftSyntax](https://github.com/apple/swift-syntax)** (602.0.0) - Syntax parsing
- **CryptoKit** - Project path hashing
- **swift-log** (via MCP Swift SDK) - Logging

## Contributing

Issues and Pull Requests are welcome!

For the maintainer release procedure (version bump + Homebrew Formula, with diagrams), see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT License - See [LICENSE](LICENSE) file for details

## Acknowledgments

- [Model Context Protocol](https://modelcontextprotocol.io/) - MCP protocol specification
- [SwiftSyntax](https://github.com/apple/swift-syntax) - Swift syntax parsing library
- [Anthropic](https://www.anthropic.com/) - Claude AI
