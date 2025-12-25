# 文書フォーマットテンプレート

このディレクトリには、プロジェクトで使用する文書のフォーマットテンプレートを格納しています。

---

## テンプレート一覧

| ファイル | 用途 | 使用タイミング |
|---------|------|---------------|
| [design_format.md](design_format.md) | 設計書テンプレート | 新しい設計書（DES-xxx）を作成する時 |
| [spec_format.md](spec_format.md) | 要件定義テンプレート | 新しい要件定義（REQ-xxx）を作成する時 |
| [plan_format.md](plan_format.md) | 計画書テンプレート | 実装計画を作成する時 |
| [code_header_format.md](code_header_format.md) | コードヘッダーテンプレート | Swiftファイルにヘッダーコメントを追加する時 |

---

## 使い方

### 設計書を作成する場合

1. `design_format.md` を参照
2. 新しいファイルを `swift-selena/design/` に作成
3. ファイル名は `DES-XXX_<機能名>.md` の形式
4. テンプレートに従って記述

### 要件定義を作成する場合

1. `spec_format.md` を参照
2. 新しいファイルを `swift-selena/requirements/` に作成
3. ファイル名は `REQ-XXX_<機能名>.md` の形式
4. テンプレートに従って記述

---

## 命名規則

| 文書タイプ | プレフィックス | 例 |
|-----------|---------------|-----|
| 設計書 | DES-XXX | DES-101_System_Architecture.md |
| 要件定義 | REQ-XXX | REQ-001_Overall_Requirements.md |
| 計画書 | (なし) | PLAN.md, v0.6.0_implementation_plan.md |

---

## 関連ドキュメント

- [設計書一覧](../swift-selena/design/README.md)
- [要件定義一覧](../swift-selena/requirements/README.md)
