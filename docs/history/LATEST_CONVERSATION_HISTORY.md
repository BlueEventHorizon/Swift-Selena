# 最新開発履歴サマリー（v0.6.1）

**作成日**: 2025-12-06
**対象**: 次のClaude Codeセッション用
**Document Version**: 2.0

---

## v0.6.1 実装内容

### DebugRunnerパス問題修正
- 開発者のパス（`/Users/k_terada/`）がハードコードされていた問題を修正
- `detectProjectPath()`メソッド追加で動的にプロジェクトルートを検出
- `#if DEBUG`で囲まれているためrelease版には影響なし

### Makefile導入
```makefile
make build              # デバッグビルド
make build-release      # リリースビルド
make register-debug     # デバッグ版登録（Swift-Selena自体に）
make register-release TARGET=/path  # リリース版登録（他プロジェクトに）
make unregister-debug   # デバッグ版登録解除
make unregister-release TARGET=/path  # リリース版登録解除
make clean              # ビルド成果物クリーン
```

### プロジェクト構造改善
```
Swift-Selena/
├── Makefile                 # 新規（ビルド・登録用）
├── Tools/
│   ├── Scripts/             # スクリプト移動先
│   │   ├── register-selena-to-claude-code.sh
│   │   ├── register-selena-to-claude-code-debug.sh
│   │   └── register-mcp-to-claude-desktop.sh
│   └── Client/
│       └── Makefile         # 元のMakefile（クライアントアプリ用）
```

### ドキュメント更新
- README.md, README.ja.md: makeコマンドでの操作方法に更新
- CLAUDE.md: DEBUGビルドテスト方法を更新
- .claude/commands/create-code-headers.md: Swift-Selena用に修正
- CHANGELOG.md: v0.6.0/v0.6.1追記

---

## 重要な知見

### MCPツールのコンテキスト消費
- debug版とrelease版の両方を登録すると約25.5kトークン消費
- 開発時はdebug版のみ、本番時はrelease版のみ登録を推奨

### スクリプトの使い分け
- **release版**: 他のプロジェクト（CCMonitor等）に登録 → 引数必須
- **debug版**: Swift-Selenaプロジェクト自体に登録 → 引数不要

---

## 現在の構成

- **ツール数**: 18
- **バージョン**: 0.6.1（開発中）
- **ブランチ**: feature/0_6_1

---

## 次のバージョン（v0.6.0計画中）

- Code Header DB機能
- search_code_headers（意図ベース検索）
- get_code_header_stats（統計情報）
- Apple NaturalLanguage統合

---

**参考資料**: `docs/history/CONVERSATION_HISTORY.md` - 詳細な開発履歴
