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

> **Three key points**
> 1. Capture **commit 1's SHA before the merge** with `git rev-parse HEAD` — this is why the Formula can be written up front.
> 2. Write **commit 1's SHA** into the Formula's `revision`, and **tag commit 1** (not the merge commit).
> 3. Merge into `main` with **`--no-ff`** — a squash / rebase merge would discard commit 1's SHA.

### Flowchart (step checklist)

```mermaid
flowchart TD
    subgraph PH1["Phase 1 — bump PR (on develop, single PR)"]
        A["Commit 1: Constants + CHANGELOG bump<br/>(/forge:update-version)"]
        B["git rev-parse HEAD<br/>→ get SHA of commit 1"]
        C["Commit 2: update Formula<br/>tag=0.6.12 / revision=SHA1"]
        D["verify_version_consistency.sh<br/>+ brew style"]
        E["push → open PR → merge"]
    end

    subgraph PH2["Phase 2 — merge to main + tag (on main, one merge)"]
        F["Merge develop into main with --no-ff<br/>preserves SHA1 (no squash/rebase)"]
        G["git tag 0.6.12 on commit 1<br/>(not the merge commit) → push"]
        H{"rev-parse 0.6.12<br/>== Formula revision ?"}
        K["Delete & recreate the tag<br/>git tag -d → retag on commit 1"]
        I["brew install --build-from-source"]
        J["serverInfo.version == 0.6.12<br/>drift resolved"]
    end

    A --> B --> C --> D --> E --> F --> G --> H
    H -->|match| I --> J
    H -->|mismatch| K --> G

    style B fill:#fff3cd
    style C fill:#fff3cd
    style F fill:#ffe0e0
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
    Y->>D: Commit 1 ... Constants + CHANGELOG bump (/forge:update-version)
    Y->>D: git rev-parse HEAD to get SHA of commit 1
    Note over Y,D: SHA1 is fixed before the merge, so it can be written into the Formula
    Y->>D: Commit 2 ... update Formula tag=0.6.12 / revision=SHA1
    Y->>D: verify + brew style → push → merge PR
    end

    rect rgb(232, 245, 233)
    Note over Y,M: Phase 2 — merge to main + tag (main, one merge)
    Y->>M: Merge develop with --no-ff (preserves SHA1, no squash)
    Y->>T: git tag 0.6.12 on commit 1 (not the merge commit)
    T-->>Y: verify rev-parse 0.6.12 == Formula revision
    end

    Y->>BR: brew install --build-from-source
    BR->>M: read the latest Formula (tag=0.6.12 / revision=SHA1)
    BR->>T: fetch & build the source at revision=SHA1
    BR-->>Y: serverInfo.version == 0.6.12 (drift resolved)
```
