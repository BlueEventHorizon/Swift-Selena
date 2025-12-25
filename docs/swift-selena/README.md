# Swift-Selena 固有ドキュメント

このディレクトリには、Swift-Selenaプロジェクト固有のドキュメントを格納しています。

汎用的なMCP知識は [mcp-guide/](../mcp-guide/README.md) を参照してください。

---

## ディレクトリ構造

```
swift-selena/
├── design/             # 設計文書
│   ├── features/       # 機能別設計
│   └── DES-*.md        # システム設計
├── requirements/       # 要件定義
├── plans/              # 開発計画
└── MCP_LSP_LEARNINGS.md  # LSP統合で得た知見
```

---

## 設計文書 (design/)

### システム設計

| ファイル | 内容 |
|---------|------|
| [DES-101_System_Architecture.md](design/DES-101_System_Architecture.md) | システム全体アーキテクチャ |
| [DES-102_LSP_Integration_Design.md](design/DES-102_LSP_Integration_Design.md) | LSP統合設計 |
| [DES-103_Tool_Implementation_Design.md](design/DES-103_Tool_Implementation_Design.md) | ツール実装パターン |

### 機能別設計 (design/features/)

| ファイル | 内容 |
|---------|------|
| DES-004_swift_toc_generation_design.md | ToC生成機能 |
| DES-005_code_header_generation_design.md | コードヘッダー生成 |
| DES-006_code_header_db_design_v2.md | コードヘッダーDB（v2） |

---

## 要件定義 (requirements/)

| ファイル | 内容 |
|---------|------|
| REQ-001_Swift_Selena_Overall_Requirements.md | 全体要件 |
| REQ-002_LSP_Integration_v0.5.x.md | LSP統合要件 |
| REQ-003_Core_Features_Requirements.md | コア機能要件 |
| REQ-004_Code_Header_DB_v0.6.x.md | コードヘッダーDB要件 |

---

## 開発計画 (plans/)

| ファイル | 内容 |
|---------|------|
| [PLAN.md](plans/PLAN.md) | 全体開発計画・ロードマップ |
| v0.6.0_implementation_plan.md | v0.6.0実装計画 |

---

## LSP統合知見

**[MCP_LSP_LEARNINGS.md](MCP_LSP_LEARNINGS.md)**

LSP（Language Server Protocol）統合で得た知見を記録。

- SourceKit-LSPのプロジェクト対応状況
- XcodeプロジェクトでのLSP動作制限
- 非同期通知の処理方法
- 複数プロジェクト対応

---

## 関連ドキュメント

- [汎用MCPガイド](../mcp-guide/README.md) - MCP実装の基礎知識
- [対話履歴](../history/CONVERSATION_HISTORY.md) - 設計判断の経緯
