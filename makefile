.PHONY: help build build-release register-debug register-desktop unregister-debug unregister-desktop install-client-makefile clean

default: help

help:
	@echo "Swift-Selena Makefile"
	@echo ""
	@echo "Build commands:"
	@echo "  make build          - Build debug version"
	@echo "  make build-release  - Build release version"
	@echo "  make clean          - Clean build artifacts"
	@echo ""
	@echo "Register commands:"
	@echo "  make register-debug     - Build & register DEBUG version to this project's Claude Code"
	@echo "  make register-desktop   - Register to Claude Desktop"
	@echo ""
	@echo "  For release version, use scripts directly:"
	@echo "    ./register-selena-to-claude-code.sh /path/to/project"
	@echo "    ./unregister-selena-from-claude-code.sh [/path/to/project]"
	@echo ""
	@echo "Unregister commands:"
	@echo "  make unregister-debug   - Unregister DEBUG version from this project"
	@echo "  make unregister-desktop - Unregister from Claude Desktop"
	@echo ""
	@echo "Client tools:"
	@echo "  make install-client-makefile TARGET=<path> - Install client Makefile to target project"

# ビルド
build:
	swift build

build-release:
	rm -rf .build/release
	swift build -c release -Xswiftc -Osize

clean:
	swift package clean

# 登録コマンド
register-debug:
	@./Tools/Scripts/register-selena-to-claude-code-debug.sh

register-desktop:
	@./Tools/Scripts/register-mcp-to-claude-desktop.sh

# 登録解除コマンド
unregister-debug:
	@echo "Unregistering swift-selena-debug from Claude Code..."
	@claude mcp remove swift-selena-debug 2>/dev/null || echo "swift-selena-debug was not registered"
	@echo "Done. Restart Claude Code to apply changes."

unregister-desktop:
	@echo "Unregistering swift-selena from Claude Desktop..."
	@CONFIG_FILE="$$HOME/Library/Application Support/Claude/claude_desktop_config.json"; \
	if [ -f "$$CONFIG_FILE" ] && command -v jq &> /dev/null; then \
		jq 'del(.mcpServers."swift-selena")' "$$CONFIG_FILE" > "$$CONFIG_FILE.tmp" && \
		mv "$$CONFIG_FILE.tmp" "$$CONFIG_FILE" && \
		echo "Removed swift-selena from Claude Desktop config."; \
	else \
		echo "Config file not found or jq not installed. Please edit manually."; \
	fi
	@echo "Done. Restart Claude Desktop to apply changes."

# クライアントツール
install-client-makefile:
	@if [ -z "$(TARGET)" ]; then \
		echo "Error: TARGET is required"; \
		echo "Usage: make install-client-makefile TARGET=/path/to/your/project"; \
		exit 1; \
	fi
	@if [ ! -d "$(TARGET)" ]; then \
		echo "Error: Directory not found: $(TARGET)"; \
		exit 1; \
	fi
	@if [ -f "$(TARGET)/Makefile" ]; then \
		echo "Warning: Makefile already exists at $(TARGET)/Makefile"; \
		read -p "Overwrite? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1; \
	fi
	@cp Tools/Client/Makefile "$(TARGET)/Makefile"
	@echo "Installed client Makefile to $(TARGET)/Makefile"
	@echo ""
	@echo "Available commands in target project:"
	@echo "  make connect_gemini     - Connect gemini-cli MCP tool"
	@echo "  make connect_figma      - Connect Figma Dev Mode MCP server"
	@echo "  make connect_serena     - Connect serena MCP server"
