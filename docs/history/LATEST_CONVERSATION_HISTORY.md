# 最新開発履歴サマリー（v0.6.1）

**作成日**: 2025-12-06
**対象**: 次のClaude Codeセッション用
**Document Version**: 2.1

---

## v0.6.1 主要変更

### ツール削減: 18個 → 13個（28%削減）

**削除したツール（5個）:**
- `add_note` / `search_notes` - 未使用
- `read_symbol` - Claudeの`Read`で代替可能
- `set_analysis_mode` / `think_about_analysis` - 効果不明

**残したツール（13個）:**
`initialize_project`, `find_files`, `search_code`, `search_files_without_pattern`, `list_symbols`, `find_symbol_definition`, `list_property_wrappers`, `list_protocol_conformances`, `list_extensions`, `analyze_imports`, `get_type_hierarchy`, `find_test_cases`, `find_type_usages`

### Makefile・スクリプト構成

```
Swift-Selena/
├── register-selena-to-claude-code.sh      # Release版登録
├── unregister-selena-from-claude-code.sh  # Release版解除
├── Makefile
├── Tools/Scripts/
│   ├── register-selena-to-claude-code-debug.sh
│   └── register-mcp-to-claude-desktop.sh
```

**使い方:**
```bash
# Debug版
make register-debug
make unregister-debug

# Release版（スクリプト直接実行）
./register-selena-to-claude-code.sh /path/to/project
./unregister-selena-from-claude-code.sh [/path/to/project]
```

---

## 重要な知見

### ツール削減の判断基準
1. Claude標準機能で代替可能か？
2. 実際に使われているか？
3. 精度の違いはあるか？（`find_type_usages`は`search_code`よりノイズ半減）
4. ユースケースが異なるか？

### Xcodeプロジェクト対応
- 13ツール全て正常動作（CCMonitorで検証済み）
- 削除した`find_symbol_references`のみがXcode非対応だった

### MCPコンテキスト消費
- debug版とrelease版の両方登録で約25kトークン消費
- 開発時はdebug版のみ、本番時はrelease版のみ推奨

---

## 現在の構成

- **ツール数**: 13
- **バージョン**: 0.6.1（開発中）
- **ブランチ**: feature/0_6_1

---

## 次のバージョン

**v0.7.0（計画中）:**
- Code Header DB機能
- search_code_headers（意図ベース検索）
- get_code_header_stats（統計情報）
- Apple NaturalLanguage統合（Phase 1）

---

**参考**: `docs/history/CONVERSATION_HISTORY.md` - 詳細な開発履歴
