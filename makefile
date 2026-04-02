.PHONY: help build build-release register-release unregister-release register-debug unregister-debug register-desktop unregister-desktop clean

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
	@echo "  make register-release   - Register RELEASE version to Claude Code (prompts for path)"
	@echo "  make register-debug     - Build & register DEBUG version to this project's Claude Code"
	@echo "  make register-desktop   - Register to Claude Desktop"
	@echo ""
	@echo "Unregister commands:"
	@echo "  make unregister-release - Unregister RELEASE version from Claude Code (prompts for path)"
	@echo "  make unregister-debug   - Unregister DEBUG version from this project"
	@echo "  make unregister-desktop - Unregister from Claude Desktop"
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

# 登録コマンド
register-release:
	@read -p "登録先プロジェクトのパスを入力してください: " target_path; \
	./scripts/register-release.sh "$$target_path"

unregister-release:
	@read -p "登録解除するプロジェクトのパスを入力してください（空白でカレントディレクトリ）: " target_path; \
	./scripts/unregister-release.sh "$$target_path"

register-debug:
	@./scripts/register-debug.sh

register-desktop:
	@./scripts/register-desktop.sh

# 登録解除コマンド
unregister-debug:
	@echo "Unregistering swift-selena-debug from Claude Code..."
	@claude mcp remove swift-selena-debug 2>/dev/null || echo "swift-selena-debug was not registered"
	@echo "Done. Restart Claude Code to apply changes."

unregister-desktop:
	@./scripts/unregister-desktop.sh
