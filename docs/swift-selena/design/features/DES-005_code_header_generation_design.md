# Code Headerフォーマット生成システム 設計書

**設計ID**: DES-005
**関連設計**: DES-004（方針転換元）
**作成日**: 2025-10-20
**更新日**: 2025-10-20

---

## 1. 概要

### 1.1 目的

Swiftコードベース（Tools/Library/Domain/App/Infrastructure/DI）の全ファイルに、AI検索可能なCode Headerフォーマットを自動生成し、Swift-Selena MCP DB構築の基盤を提供する。

### 1.2 背景

**DES-004（swift_toc.md方式）の問題**:
- AI推論精度40%（「推論困難」が多発）
- list_symbolsだけでは情報不足
- ToCファイルの更新忘れリスク

**Code Headerフォーマット方式の優位性**:
- コード全体を読んで正確に理解（精度100%）
- ファイルとヘッダーが同期（更新忘れなし）
- 標準的なファイルヘッダー形式（既存ヘッダーと互換）
- Swift-Selena直接読み取り可能（ToCファイル不要）

### 1.3 設計方針

1. **既存ヘッダー互換**: `//` コメント、スペース2つ
2. **マーカーベース判定**: `[Code Header Format]`で適用済み判定
3. **並行処理**: 複数Agent同時起動で高速化
4. **モード制御**: デフォルト/--update/--changed
5. **完全理解**: コード全体を読み、Testも確認して生成

---

## 2. アーキテクチャ

### 2.1 システム構成

```
/create-code-headers コマンド
    ↓
ファイルスキャン（モード別）
    ↓
複数 code-header-generator Agent（並行起動）
    ↓ 各Agent
ファイル読み込み → マーカー確認 → コード理解 → ヘッダー生成 → Edit()
    ↓
完了報告
```

### 2.2 モジュール構成

| モジュール | 責務 | ツール |
|-----------|------|--------|
| **Command** | ファイルスキャン、Agent起動、進捗管理 | Glob, Bash(git), Task |
| **Agent** | 1ファイルのヘッダー生成 | Read, Edit |
| **Format** | フォーマット仕様定義 | なし（ドキュメント） |

---

## 3. フォーマット仕様

### 3.1 Code Header Format

```swift
//
//  [ファイル名].swift
//  [プロジェクト名]
//
//  Created by ... on YYYY/MM/DD.
//
//  [Code Header Format]
//
//  目的
//  - [目的1]
//  - [目的2]
//
//  主要機能
//  - [機能1]
//  - [機能2]
//
//  含まれる型（該当する場合のみ）
//  - [型名]: [説明]
//
//  関連型（該当する場合のみ）
//  - [型名], [型名]
//

import Foundation
```

### 3.2 マーカーの役割

**`[Code Header Format]` マーカー**:
- フォーマット適用済み判定に使用
- skipモード時の判定基準
- Swift-Selena DB構築時の識別子

### 3.3 原則

- **簡潔かつ十分な情報**（冗長を避け、必要な情報は必ず含める）
- **生成AIが知っていること、容易に類推できることは記述しない**
- **関数名は書かない**（コードを読めば分かる）
- **Protocol準拠は書かない**（Swift-Selenaで分かる）

---

## 4. Agent設計

### 4.1 code-header-generator Agent

**役割**: 1ファイルのCode Headerフォーマット生成

**実行フロー**:
1. ファイル読み込み
2. `[Code Header Format]`マーカー確認
3. モード判定（skip/update）
4. コード理解（実装、Test、既存コメント）
5. ヘッダー生成
6. Edit()でファイル更新

**重要制約**:
- [CRITICAL] 既存の関数・型のDocCコメント（`///`）は絶対に消さない
- [CRITICAL] 既存の実装コメント（`//`）も保持する
- Copyrightヘッダーは変更しない

---

## 5. Command設計

### 5.1 /create-code-headers

**モード**:
```
/create-code-headers           # デフォルト（既存スキップ）
/create-code-headers --update  # 全ファイル上書き
/create-code-headers --changed # git変更ファイルのみ
```

### 5.2 ファイルスキャン

#### デフォルト・--update
```
Glob("Tools/**/*.swift")
Glob("Library/**/*.swift")
Glob("Domain/**/*.swift")
Glob("App/**/*.swift")
Glob("Infrastructure/**/*.swift")
Glob("DI/**/*.swift")
```

#### --changed
```bash
git status --porcelain
→ .swiftファイルのみ抽出
→ Mock/Test除外
```

### 5.3 並行処理

**重要**: 複数Task toolを1つのメッセージで同時実行

```
Task(prompt="対象ファイル: AppVersion.swift")
Task(prompt="対象ファイル: StreamManager.swift")
Task(prompt="対象ファイル: MockAssertion.swift")
...（5-10 Agent同時起動）
```

---

## 6. モード設計

### 6.1 モード別動作

| モード | スキャン対象 | マーカーあり | マーカーなし |
|--------|------------|------------|------------|
| デフォルト | 全ファイル | スキップ | 生成 |
| --update | 全ファイル | 上書き生成 | 生成 |
| --changed | git変更ファイル | スキップ | 生成 |

### 6.2 モード指定方法の重要な注意

**[CRITICAL] promptでの`モード: skip`明示は禁止**

理由: Agentが「skip = 何もしない」と誤解する

**正しい方法**:
- デフォルト: モード指定なし（Agent内部でskipモード動作）
- 更新: `モード: update` のみ明示

---

## 7. 生成方法

### 7.1 コード理解プロセス

1. **Read()でファイル全体を読み込む**
2. **コードを理解する**（実装内容、ロジック、構造を把握）
3. **Testファイルがあれば読んで使用例・意図を理解**
4. **既存コメントがあれば参考にする**（ただし鵜呑みにしない）
5. **理解した内容から目的・機能を記述**

**重要**: 「推論」ではなく「理解」

---

## 8. Swift-Selena連携

### 8.1 Phase 1（現在）

**検索方法**:
```typescript
search_code("目的.*AsyncStream")
→ StreamManager.swift

search_code("主要機能.*検証")
→ ValidationRule.swift, FormValidator.swift
```

### 8.2 Phase 2（将来）

**Swift-Selena DB構築**:
1. 全SwiftファイルのCode Headerを読み取り
2. `[Code Header Format]`マーカーで識別
3. 目的・主要機能・含まれる型・関連型を抽出
4. 内部DB構築

**新規MCP Tool**:
```typescript
mcp__swift-selena__search_by_purpose(query: "電話番号フォーマット")
→ PhoneNumber+InternationalFormat.swift

mcp__swift-selena__search_by_feature(query: "バリデーション")
→ ValidationRule.swift, FormValidator.swift, LiveValidator.swift
```

---

## 9. 性能要件

### 9.1 処理時間

| ファイル数 | 並行Agent数 | 予想時間 |
|-----------|-----------|---------|
| 187件 | 10 | 約15-20分 |
| 20件（--changed） | 5 | 約3-5分 |

### 9.2 品質基準

- **理解可能性**: ヘッダーだけでファイルの目的・機能が分かる
- **検索可能性**: 自然言語検索にヒットする
- **簡潔性**: 冗長な表現はない
- **十分性**: 必要な情報は全て含まれている

---

## 10. エラーハンドリング

### 10.1 ファイルスキャンエラー

- ディレクトリ不存在 → 警告表示、該当ディレクトリスキップ
- 権限エラー → エラー報告、処理中断

### 10.2 Agent実行エラー

- ファイル読み込み失敗 → 該当ファイルスキップ、警告
- Edit()失敗 → 該当ファイルスキップ、エラー報告

### 10.3 git statusエラー（--changedモード時）

- git未初期化 → エラー報告、デフォルトモードへ降格提案
- gitコマンド失敗 → エラー報告、処理中断

---

## 11. 運用

### 11.1 更新タイミング

**必須**:
- 新規Swiftファイル追加時（`/create-code-headers --changed`）

**推奨**:
- 大規模リファクタリング後（`/create-code-headers --update`）

### 11.2 検証方法

生成後の品質確認:
```
search_code("\\[Code Header Format\\]")
→ フォーマット適用済みファイル数を確認
```

---

## 12. DES-004との比較

| 項目 | DES-004（swift_toc.md） | DES-005（Code Header） |
|------|----------------------|---------------------|
| 生成物 | 1つのToCファイル | 各ファイルにヘッダー |
| AI推論精度 | 40%（推論困難多発） | 100%（コード理解） |
| メンテナンス | 月1回再生成必要 | ファイルと同期 |
| 検索方法 | search_code(swift_toc.md) | search_code(各ファイル) |
| 標準準拠 | 独自形式 | 既存ヘッダー互換 |
| 更新忘れ | あり得る | なし |
| 処理時間 | 約1分 | 約15-20分（初回のみ） |

**結論**: DES-005の方が長期的に優れている

---

## 13. 関連ドキュメント

- `docs/templates/code_header_format.md` - フォーマット仕様
- `.claude/agents/code-header-generator.md` - Agent定義
- `.claude/commands/create-code-headers.md` - Command定義
- `project/tool_design/DES-004_swift_toc_generation_design.md` - 前身設計
- `project/tool_design/DES-004_HISTORY.md` - DES-004の経緯

---

## 14. まとめ

Code Headerフォーマット生成システムは、DES-004の課題（AI推論精度、更新忘れ）を根本的に解決し、以下を実現する：

1. **100%正確なドキュメント**: コード全体を読んで理解
2. **自動同期**: ファイルとヘッダーが常に一体
3. **標準準拠**: 既存ヘッダー形式と互換
4. **Swift-Selena連携**: 将来のDB構築基盤
5. **効率的運用**: --changedオプションで差分更新

長期的に持続可能なAI検索基盤として設計されている。
