# Swift-Selena ドキュメント

このディレクトリには、Swift-Selenaプロジェクトの全ドキュメントが格納されています。

---

## ディレクトリ構造

```
docs/
├── mcp-guide/          # 汎用MCPガイド（テンプレート化可能）
├── swift-selena/       # Swift-Selena固有のドキュメント
├── templates/          # 文書フォーマットテンプレート
└── history/            # 対話履歴・開発ログ
```

---

## ディレクトリ別説明

### [mcp-guide/](mcp-guide/README.md)

**汎用的なMCPサーバー開発ガイド**

他のMCPサーバープロジェクトでも活用できる内容です。

| ファイル | 内容 |
|---------|------|
| MCP-Implementation-Guide.md | MCP実装の詳細ガイド |
| MCP-SDK-Deep-Dive.md | Swift MCP SDKの詳細解説 |
| MCP-Best-Practices.md | 開発ベストプラクティス |

### [swift-selena/](swift-selena/README.md)

**Swift-Selena固有のドキュメント**

| サブディレクトリ | 内容 |
|----------------|------|
| design/ | 設計文書（DES-xxx） |
| requirements/ | 要件定義（REQ-xxx） |
| plans/ | 開発計画 |

### [templates/](templates/README.md)

**文書フォーマットテンプレート**

新しい設計書・要件書を作成する際のテンプレート。

### [history/](history/)

**対話履歴・開発ログ**

| ファイル | 内容 |
|---------|------|
| CONVERSATION_HISTORY.md | 重要な設計判断・検討履歴 |
| archive/ | アーカイブ済み履歴 |

---

## クイックリンク

### 初めての方

1. [MCP実装ガイド](mcp-guide/MCP-Implementation-Guide.md) - MCPサーバーの作り方
2. [システムアーキテクチャ](swift-selena/design/DES-101_System_Architecture.md) - Swift-Selenaの全体構成

### 開発者向け

1. [MCPベストプラクティス](mcp-guide/MCP-Best-Practices.md) - 失敗パターンと対策
2. [LSP統合設計](swift-selena/design/DES-102_LSP_Integration_Design.md) - LSP統合の詳細
3. [開発計画](swift-selena/plans/PLAN.md) - 今後のロードマップ

### 文書作成

1. [設計書テンプレート](templates/design_format.md)
2. [要件定義テンプレート](templates/spec_format.md)
3. [計画書テンプレート](templates/plan_format.md)

---

## 更新履歴

- **2025-12-26**: ディレクトリ再編成（汎用/固有の分離）
