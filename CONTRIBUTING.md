# Contributing

Issues and Pull Requests are welcome!

For usage and Homebrew installation, see the [README](README_en.md). This guide covers **building from source**, **local development setup**, and the **release procedure**.

Japanese version: [CONTRIBUTING.ja.md](CONTRIBUTING.ja.md)

## Building from source

```bash
git clone https://github.com/BlueEventHorizon/Swift-Selena.git
cd Swift-Selena

# Release build (production)
make build-release
# Or directly: swift build -c release -Xswiftc -Osize

# Debug build
make build
```

The build artifact is generated at `.build/release/Swift-Selena` (or `.build/debug/Swift-Selena`).

### Available Make Commands

```bash
make help  # Show all available commands
```

| Command | Target | Description |
|---------|--------|-------------|
| `make build` | — | Build debug version |
| `make build-release` | — | Build release version |
| `make clean` | — | Clean build artifacts |
| `make connect_gemini` | Claude Code | Connect gemini-cli MCP server |
| `make disconnect_gemini` | Claude Code | Disconnect gemini-cli MCP server |
| `make register-release` | Claude Code | Register RELEASE version (prompts for project path) |
| `make unregister-release` | Claude Code | Unregister RELEASE version (prompts for project path) |
| `make register-debug` | Claude Code | Build & register DEBUG version to the Swift-Selena project |
| `make unregister-debug` | Claude Code | Unregister DEBUG version from the Swift-Selena project |
| `make register-desktop` | Claude Desktop | Register to Claude Desktop |
| `make unregister-desktop` | Claude Desktop | Unregister from Claude Desktop |

## Development setup

To register your locally-built binary with Claude (instead of the Homebrew release), use either the make helpers or manual configuration.

### Using make (recommended for development)

```bash
# Claude Desktop
make register-desktop

# Claude Code — register to a target project
make register-release       # → prompts for the target project path

# Claude Code — register the DEBUG build to the Swift-Selena project itself
make register-debug
```

Unregister:

```bash
make unregister-desktop
make unregister-release      # → prompts for the target project path (blank = current dir)
make unregister-debug
```

### Manual configuration

**Claude Desktop** — edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "swift-selena": {
      "command": "/path/to/Swift-Selena/.build/release/Swift-Selena",
      "env": { "MCP_CLIENT_ID": "claude-desktop" }
    }
  },
  "isUsingBuiltInNodeForMcp": true
}
```

Replace `/path/to/Swift-Selena` with the actual path, then restart Claude Desktop.

**Claude Code** — in your target project directory:

```bash
claude mcp add swift-selena -- /path/to/Swift-Selena/.build/release/Swift-Selena
# Global (all projects):
claude mcp add -s user swift-selena -- /path/to/Swift-Selena/.build/release/Swift-Selena
```

## Release procedure (maintainers)

Steps for bumping the version and the Homebrew Formula. **The authoritative, executable procedure lives in [CLAUDE.md](CLAUDE.md)** (the release-flow section); the diagrams below are a visual aid.

> **Key points**
> 1. Put the release tag on **`main`'s first-parent line** (the merge commit / HEAD right after merging to `main`), so tags line up along `main`.
> 2. **Do not write `revision:` in the Formula** — only `tag:`. The tagged commit contains the Formula itself, so its SHA cannot be written into it (circular). Without `revision`, a tag/revision mismatch (Issue #38) cannot happen.
> 3. Tag **right after** merging to `main` (the Formula's `tag:` points at a tag that does not exist until then).

### Flowchart (step checklist)

```mermaid
flowchart TD
    subgraph PH1["Phase 1 — bump PR (on develop, single PR)"]
        A["Constants + CHANGELOG bump<br/>(/forge:update-version)"]
        C["Formula tag=0.6.12<br/>(no revision)"]
        D["verify_version_consistency.sh<br/>+ brew style"]
        E["push → open PR → merge"]
    end

    subgraph PH2["Phase 2 — merge to main + tag (on main)"]
        F["Merge develop into main → push"]
        G["git tag 0.6.12 on main HEAD<br/>→ push (right after the merge)"]
        H{"verify_release_tag.sh<br/>tag on main first-parent line ?"}
        K["Delete & recreate the tag<br/>git tag -d → retag on main HEAD"]
        I["brew install --build-from-source"]
        J["serverInfo.version == 0.6.12"]
    end

    A --> C --> D --> E --> F --> G --> H
    H -->|ok| I --> J
    H -->|ng| K --> G

    style C fill:#fff3cd
    style G fill:#fff3cd
```

### Sequence diagram (timing and the "why")

```mermaid
sequenceDiagram
    participant Y as You / AI
    participant D as develop
    participant M as main
    participant T as tag 0.6.12
    participant BR as brew install

    rect rgb(230, 245, 255)
    Note over Y,D: Phase 1 — bump PR (develop, single PR)
    Y->>D: Constants + CHANGELOG bump (/forge:update-version)
    Y->>D: Formula tag=0.6.12 (no revision)
    Y->>D: verify + brew style → push → merge PR
    end

    rect rgb(232, 245, 233)
    Note over Y,M: Phase 2 — merge to main + tag
    Y->>M: Merge develop → push
    Y->>T: git tag 0.6.12 on main HEAD → push
    T-->>Y: verify_release_tag.sh (tag is on main's first-parent line)
    end

    Y->>BR: brew install --build-from-source
    BR->>M: read the latest Formula (tag=0.6.12)
    BR->>T: fetch & build the source at tag 0.6.12
    BR-->>Y: serverInfo.version == 0.6.12
```
