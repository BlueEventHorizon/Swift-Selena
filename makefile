.PHONY: help connect_gemini connect_figma disconnect_figma connect_serena disconnect_serena

default: help

help:
	@echo "  make connect_gemini    - Connect gemini-cli MCP tool to Claude Code"
	@echo "  make disconnect_gemini - Disconnect gemini-cli MCP tool from Claude Code"
	@echo "  make connect_figma     - Connect Figma Dev Mode MCP server to Claude Code"
	@echo "  make disconnect_figma	- Disconnect Figma Dev Mode MCP server from Claude Code"
	@echo "  make connect_serena	- Connect serena MCP server to Claude Code"
	@echo "  make disconnect_serena	- Disconnect serena MCP server from Claude Code"

connect_gemini:
	@echo "Connecting gemini-cli MCP tool to Claude Code..."
	claude mcp add gemini-cli -s user -- npx -y gemini-mcp-tool

disconnect_gemini:
	@echo "Disconnecting gemini-cli MCP tool from Claude Code..."
	claude mcp remove gemini-cli

connect_figma:
	@echo "Connecting Figma Dev Mode MCP server to Claude Code..."
	claude mcp add --transport sse figma-dev-mode-mcp-server http://127.0.0.1:3845/sse

disconnect_figma:
	@echo "Disconnecting Figma Dev Mode MCP server from Claude Code..."
	claude mcp remove figma-dev-mode-mcp-server

connect_serena:
	@if [ -n "$$SERENA_PATH" ]; then \
		echo "Connecting local serena from $$SERENA_PATH to Claude Code..."; \
		claude mcp add serena -- uv run --directory $$SERENA_PATH serena-mcp-server --project $$PWD; \
	else \
		echo "❌ No local serena"; \
	fi

disconnect_serena:
	@echo "Disconnecting serena MCP server from Claude Code..."
	claude mcp remove serena