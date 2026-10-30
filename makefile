.PHONY: help build build-release connect_gemini disconnect_gemini register-claude unregister-claude register-claude-app unregister-claude-app register-cursor unregister-cursor register-codex unregister-codex register-claude-debug unregister-claude-debug clean

default: help

help:
	@echo "Swift-Selena Makefile"
	@echo ""
	@echo "Build commands:"
	@echo "  make build          - Build debug version"
	@echo "  make build-release  - Build release version"
	@echo "  make clean          - Clean build artifacts"
	@echo ""
	@echo "  make connect_gemini          - Connect gemini-cli MCP server to Claude Code"
	@echo "  make disconnect_gemini       - Disconnect gemini-cli MCP server from Claude Code"
	@echo ""
	@echo "Register commands:"
	@echo "  make register-claude        - Register RELEASE version to Claude Code (asks for a project path; leave empty for all projects = user scope)"
	@echo "  make register-claude-app    - Register RELEASE version to Claude Desktop app"
	@echo "  make register-cursor        - Register RELEASE version to Cursor (asks for a project path; leave empty for ~/.cursor/mcp.json)"
	@echo "  make register-codex         - Register RELEASE version to Codex (~/.codex/config.toml, all projects)"
	@echo "  make register-claude-debug  - Build & register DEBUG version to this project's Claude Code"
	@echo ""
	@echo "Unregister commands:"
	@echo "  make unregister-claude        - Unregister RELEASE version from Claude Code (asks for a project path; leave empty for user scope)"
	@echo "  make unregister-claude-app    - Unregister from Claude Desktop app"
	@echo "  make unregister-cursor        - Unregister from Cursor (asks for a project path; leave empty for ~/.cursor/mcp.json)"
	@echo "  make unregister-codex         - Unregister from Codex (~/.codex/config.toml)"
	@echo "  make unregister-claude-debug  - Unregister DEBUG version from this project"
	@echo ""

# ビルド
build:
	@echo "Clearing symbol cache (analysis logic may have changed)..."
	@rm -f ~/.swift-selena/clients/*/projects/*/memory.json 2>/dev/null || true
	swift build

build-release:
	@echo "Clearing symbol cache (analysis logic may have changed)..."
	@rm -f ~/.swift-selena/clients/*/projects/*/memory.json 2>/dev/null || true
	rm -rf .build/release
	swift build -c release -Xswiftc -Osize

clean:
	swift package clean

connect_gemini:
	@echo "Connecting gemini-cli MCP server to Claude Code..."
	claude mcp add gemini-cli -s user -- npx -y gemini-mcp-tool

disconnect_gemini:
	@echo "Disconnecting gemini-cli MCP server from Claude Code..."
	claude mcp remove gemini-cli

# 登録コマンド
register-claude:
	@read -p "登録先プロジェクトのパスを入力してください（空白で全プロジェクト共通 = user スコープ）: " target_path; \
	./scripts/register-release.sh "$$target_path"

register-claude-app:
	@./scripts/register-desktop.sh

register-cursor:
	@read -p "登録先プロジェクトのパスを入力してください（空白で全プロジェクト共通 ~/.cursor/mcp.json）: " target_path; \
	./scripts/register-cursor.sh "$$target_path"

register-codex:
	@./scripts/register-codex.sh

register-claude-debug:
	@./scripts/register-debug.sh

# 登録解除コマンド
unregister-claude:
	@read -p "登録解除するプロジェクトのパスを入力してください（空白で全プロジェクト共通 = user スコープ）: " target_path; \
	./scripts/unregister-release.sh "$$target_path"

unregister-claude-app:
	@./scripts/unregister-desktop.sh

unregister-cursor:
	@read -p "登録解除するプロジェクトのパスを入力してください（空白で全プロジェクト共通 ~/.cursor/mcp.json）: " target_path; \
	./scripts/unregister-cursor.sh "$$target_path"

unregister-codex:
	@./scripts/unregister-codex.sh

unregister-claude-debug:
	@echo "Unregistering swift-selena-debug from Claude Code..."
	@claude mcp remove swift-selena-debug 2>/dev/null || echo "swift-selena-debug was not registered"
	@echo "Done. Restart Claude Code to apply changes."
