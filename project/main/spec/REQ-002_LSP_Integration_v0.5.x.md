# REQ-002: v0.5.x LSP統合要件定義

**要件ID**: REQ-002
**作成日**: 2025-10-24
**対象**: v0.5.1〜v0.5.5（LSP統合フェーズ）
**ステータス**: 承認待ち
**関連文書**: REQ-001, DES-007, DES-008, DES-009, Hybrid-Architecture-Plan.md

---

## 1. 要求背景

### 1.1 なぜLSP統合が必要か

#### 背景：SwiftSyntaxの限界

**SwiftSyntax（v0.5.0で実装済み）の強み:**
- ✅ ビルド不要
- ✅ 高速
- ✅ 実装中コードも解析可能

**SwiftSyntaxの限界:**
- ❌ 型情報がない（`var x`の型が分からない）
- ❌ 参照検索が不正確（文字列ベース）
- ❌ 型推論ができない

**具体例:**
```swift
// ファイル1
class UserManager {
    func createUser(name: String) -> User { ... }
}

// ファイル2
let manager = UserManager()  // ← SwiftSyntax: 型が分からない
manager.createUser("Alice")  // ← LSP: UserManager.createUserと正確に分かる
```

---

#### 課題：正確な参照検索の必要性

**シーン：リファクタリング**
```swift
class UserRepository {
    func save(user: User) { ... }  // ← このメソッドの全使用箇所を知りたい
}
```

**SwiftSyntaxでの検索:**
```
find_type_usages("UserRepository")
→ UserRepository型の使用箇所は分かる

search_code("\.save")
→ .saveという文字列を検索（不正確、ノイズ多い）
```

**問題点:**
- save()メソッドの呼び出しを正確に検出できない
- 他のクラスのsave()メソッドも検出してしまう（ノイズ）
- 型推論された変数からの呼び出しを見逃す

**LSPでの解決:**
```
find_symbol_references("UserRepository.swift", line: 15, column: 10)
→ ✅ このsave()メソッドの呼び出しを型情報ベースで正確に検出
→ ✅ ノイズなし
→ ✅ 型推論された変数からの呼び出しも検出
```

---

### 1.2 ハイブリッドアーキテクチャの必然性

#### 二者択一ではない

**選択肢A: SwiftSyntaxのみ**
- ✅ ビルド不要
- ❌ 型情報なし、参照検索不正確

**選択肢B: LSPのみ**
- ✅ 型情報完全
- ❌ ビルド必要、実装中コードで使えない

**Swift-Selenaの選択: ハイブリッド**
- ✅ ビルド不要の原則を維持（SwiftSyntax）
- ✅ ビルド可能時は高度な機能（LSP）
- ✅ グレースフルデグレード

**具体的な動作:**
```
プロジェクト状態に応じて動的に切り替え:

ビルドエラーあり:
  → 17個のSwiftSyntaxツール使用
  → 構造解析は可能

ビルド可能:
  → 18個のツール使用（+find_symbol_references）
  → 型情報ベースの正確な解析
```

---

## 2. 現状の問題

### 2.1 v0.5.0時点の限界

#### 問題1: 参照検索の不正確性

**ケース:**
```swift
// MyApp全体で「save」メソッドを探したい
```

**v0.5.0の方法:**
```
search_code("func save")
→ 結果: 85箇所ヒット
→ 問題: 全クラスのsave()が混在、手動で絞り込み必要
```

**求められる機能:**
- 特定のクラスのsave()メソッドだけを検索
- 型情報で正確にフィルタリング

---

#### 問題2: 型情報の欠如

**ケース:**
```swift
struct User {
    var name: String
    var age: Int
}

// このageフィールドの型は？
```

**v0.5.0:**
```
list_symbols("User.swift")
→ [Variable] age (line 15)
→ 型情報なし ❌
```

**求められる機能:**
- フィールドの型を表示
- メソッドのシグネチャを表示

---

#### 問題3: Protocol実装の不完全性

**ケース:**
```swift
class ViewController: UIViewController, UITableViewDelegate {
    // どのメソッドをオーバーライドしている？
}
```

**v0.5.0:**
```
list_protocol_conformances("ViewController.swift")
→ Conforms to: UITableViewDelegate
→ でも、どのメソッドを実装しているかは分からない ❌
```

**求められる機能:**
- オーバーライドメソッドの列挙
- 未実装の必須メソッドの検出

---

### 2.2 開発者のペインポイント

#### ペイン1: 「このメソッド、どこで使ってる？」

**現状（v0.5.0）:**
```
1. find_type_usages("UserManager")
   → クラスの使用箇所は分かる
2. search_code("createUser")
   → 全ファイルのcreateUserを検索（ノイズ多い）
3. 手動で絞り込み 😞
```

**所要時間**: 5-10分

**理想（LSP版）:**
```
1. find_symbol_references("UserManager.swift", line: 15, column: 10)
   → このcreateUser()メソッドの呼び出しを正確に検出
```

**所要時間**: 10秒

**時間削減**: 30-60倍

---

#### ペイン2: 「このクラスの全メソッドとシグネチャは？」

**現状（v0.5.0）:**
```
list_symbols("UserManager.swift")
→ [Function] createUser (line 15)
→ [Function] deleteUser (line 25)
→ シグネチャ不明 😞
```

**手動でファイルを開いて確認が必要**

**理想（LSP版）:**
```
list_symbols("UserManager.swift")  # LSP強化版
→ [Method] createUser(name: String) -> User (line 15)
→ [Method] deleteUser(id: Int) throws (line 25)
→ シグネチャ完全表示 ✅
```

---

## 3. 要件定義

### 3.1 機能要件

#### FR-LSP-001: find_symbol_references（v0.5.2）

**要件:**
型情報ベースの正確なシンボル参照検索

**仕様:**
- 入力: ファイルパス、行番号、列番号
- 出力: 参照箇所のリスト（ファイルパス:行番号）
- LSP: textDocument/referencesリクエスト使用

**受入基準:**
- ✅ 特定メソッドの呼び出し箇所を100%検出
- ✅ 型推論された変数からの呼び出しも検出
- ✅ ノイズ（無関係なsave()等）ゼロ
- ✅ LSP利用不可時はエラーメッセージで代替案提示

**v0.5.3実績:**
- ✅ LSPState: 3件検出
- ✅ ProjectMemory: 34件検出
- ✅ 5回連続実行でクラッシュなし

---

#### FR-LSP-002: list_symbols強化（v0.5.4）

**要件:**
LSP利用可能時、シンボル一覧に型情報を含める

**仕様:**
- LSP版: textDocument/documentSymbol使用
- SwiftSyntax版: 従来通り（フォールバック）

**出力例:**
```
# LSP版（ビルド可能時）
[Class] ProjectMemory: class ProjectMemory (line 12)
[Property] projectPath: let projectPath: String (line 13)
[Method] save: func save() throws (line 232)

# SwiftSyntax版（ビルド不可時）
[Class] ProjectMemory (line 12)
[Variable] projectPath (line 13)
[Function] save (line 232)
```

**受入基準:**
- ✅ LSP版で型情報表示
- ✅ メソッドシグネチャ表示
- ✅ LSP失敗時にSwiftSyntax版で動作
- ✅ クラッシュなし

---

#### FR-LSP-003: get_type_hierarchy強化（v0.5.4）

**要件:**
LSP利用可能時、型階層にLSP型詳細を追加

**仕様:**
- LSP版: textDocument/prepareTypeHierarchy使用
- SwiftSyntax版: 従来のキャッシュベース（フォールバック）

**出力例:**
```
# LSP版
Type Hierarchy for 'ProjectMemory' (LSP enhanced):

[Class] ProjectMemory
  Location: ProjectMemory.swift:12
  Type Detail: class ProjectMemory

Inherits from: (なし)
Conforms to: Sendable

# SwiftSyntax版
Type Hierarchy for 'ProjectMemory':

[Class] ProjectMemory
  Location: ProjectMemory.swift:12

Inherits from: (なし)
Conforms to: (キャッシュから取得)
```

**受入基準:**
- ✅ LSP版でType Detail表示
- ✅ Protocol準拠情報の精度向上
- ✅ LSP失敗時にSwiftSyntax版で動作

---

#### FR-LSP-004: get_call_hierarchy（v0.5.5、将来）

**要件:**
呼び出し階層の取得

**ユースケース:**
- 「このメソッドはどこから呼ばれている？」
- 「このメソッドは何を呼んでいる？」

**仕様:**
- textDocument/prepareCallHierarchy
- textDocument/callHierarchy/incomingCalls
- textDocument/callHierarchy/outgoingCalls

---

### 3.2 非機能要件

#### NFR-LSP-001: グレースフルデグレード

**要件:**
LSP利用不可時も必ず動作すること

**ケース:**
1. ビルドエラーあり → SwiftSyntax版
2. SourceKit-LSP未インストール → SwiftSyntax版
3. LSP接続失敗 → SwiftSyntax版
4. LSPクラッシュ → SwiftSyntax版

**受入基準:**
- ✅ どのケースでもツールが動作
- ✅ エラーメッセージで代替案提示
- ✅ クラッシュしない

**v0.5.3達成状況:**
- ✅ 全ケースでフォールバック実装済み
- ✅ エラーハンドリング網羅

---

#### NFR-LSP-002: 動的ツールリスト

**要件:**
LSP利用可能性に応じてツールリストを変更

**仕様:**
```
ビルド不可:
  → 17個のSwiftSyntaxツール

ビルド可能（LSP接続成功）:
  → 18個のツール（+find_symbol_references）
  → list_symbols, get_type_hierarchy は LSP強化版で動作
```

**受入基準:**
- ✅ initialize_project後にLSP接続試行
- ✅ 接続成功時はLSPツール追加
- ✅ ツールリストが動的に変化

---

#### NFR-LSP-003: LSP接続の安定性

**要件:**
LSPプロトコルを完全準拠し、安定動作すること

**v0.5.3で解決した問題:**
1. initialized通知の欠落 → 2リクエスト後に終了
2. textDocument/didOpenの欠落 → "No language service" エラー
3. initializeレスポンス読み捨て不足 → 誤ったレスポンス解析
4. SIGPIPE → クラッシュ
5. Content-Length計算ミス → 通信失敗

**受入基準:**
- ✅ 5回以上連続実行でクラッシュなし
- ✅ LSPプロトコル完全準拠
- ✅ エラーハンドリング網羅

**v0.5.3実績:**
- ✅ 5回連続成功
- ✅ 参照検索成功（3-34件検出）

---

#### NFR-LSP-004: デバッグ可能性

**要件:**
LSP通信をログで確認でき、問題を特定できること

**実装（v0.5.3）:**
- FileLogHandler: `~/.swift-selena/logs/server.log`
- DebugRunner: プロセス内自動テスト
- 詳細ログ: LSPリクエスト・レスポンス全て記録

**受入基準:**
- ✅ tail -f でリアルタイム監視
- ✅ LSPレスポンス全体をログ出力
- ✅ Xcodeデバッガでブレークポイント設定可能

---

## 4. ユースケース

### UC-LSP-001: メソッド呼び出し箇所の完全把握

**アクター:** リファクタリング中の開発者

**前提条件:**
- プロジェクトがビルド可能
- Swift-Selena v0.5.2+使用

**メインフロー:**
```
1. 開発者: 「UserManager.createUser()の呼び出し箇所を全て教えて」

2. Claude:
   initialize_project("/path/to/project")
   → LSP接続成功

3. Claude:
   find_symbol_references(
     file_path: "UserManager.swift",
     line: 15,  // createUserメソッドの行
     column: 10
   )

4. 結果:
   Found 8 references:
     - ViewController.swift:42
     - LoginService.swift:28
     - SignupFlow.swift:15
     - ... (8箇所)

5. 開発者: 「全部で8箇所か。影響範囲が分かった。リファクタリング開始」
```

**代替フロー（LSP利用不可）:**
```
3. Claude: find_type_usages("UserManager")
   → SwiftSyntax版で検索（型レベル）

4. Claude: 「UserManager型は12箇所で使われています」
   （メソッドレベルではないが、ある程度把握可能）
```

**期待される効果:**
- リファクタリングの影響範囲を正確に把握
- 変更漏れゼロ
- 自信を持ってコード変更

---

### UC-LSP-002: 型情報付きコード理解

**アクター:** 新規参画の開発者

**シナリオ:**
既存プロジェクトのコードを理解したい

**メインフロー:**
```
1. 開発者: 「UserManagerクラスの全メソッドを教えて」

2. Claude:
   list_symbols("UserManager.swift")  # LSP版

3. 結果（LSP版、ビルド可能時）:
   Symbols in UserManager.swift (LSP enhanced):

   [Class] UserManager: class UserManager (line 10)
   [Property] repository: let repository: UserRepositoryProtocol (line 12)
   [Method] createUser: func createUser(name: String) async throws -> User (line 20)
   [Method] deleteUser: func deleteUser(id: Int) async throws (line 35)
   [Method] updateUser: func updateUser(_ user: User) async throws (line 50)

4. 開発者: 「シグネチャまで分かった。asyncメソッドだからawaitが必要だな」
```

**代替フロー（LSP利用不可）:**
```
3. 結果（SwiftSyntax版、ビルド不可時）:
   Symbols in UserManager.swift:

   [Class] UserManager (line 10)
   [Variable] repository (line 12)
   [Function] createUser (line 20)
   [Function] deleteUser (line 35)
   [Function] updateUser (line 50)

   → 型情報はないが、メソッド一覧は把握可能
```

**期待される効果:**
- コード理解時間: 30分 → 5分（6倍高速化）
- 型情報により正確な理解
- ファイルを開かずにシグネチャ確認

---

### UC-LSP-003: 継承階層の詳細把握

**アクター:** アーキテクト

**シナリオ:**
クラス設計をレビューしたい

**メインフロー:**
```
1. アーキテクト: 「UserViewControllerの階層を見せて」

2. Claude:
   get_type_hierarchy("UserViewController")  # LSP版

3. 結果（LSP版）:
   Type Hierarchy for 'UserViewController' (LSP enhanced):

   [Class] UserViewController
     Location: UserViewController.swift:15
     Type Detail: class UserViewController: BaseViewController

   Inherits from:
     └─ BaseViewController

   Conforms to:
     └─ UITableViewDelegate
     └─ UITableViewDataSource

   Overrides: (LSPから)
     └─ viewDidLoad()
     └─ viewWillAppear(_:)

4. アーキテクト: 「BaseViewControllerを継承して、2つのメソッドをオーバーライドか。設計通り」
```

**代替フロー（LSP利用不可）:**
```
3. 結果（SwiftSyntax版）:
   [Class] UserViewController
     Location: UserViewController.swift:15

   Inherits from:
     └─ BaseViewController

   Conforms to: (キャッシュから)
     └─ UITableViewDelegate
     └─ UITableViewDataSource

   → Overrides情報はないが、基本的な階層は把握可能
```

**期待される効果:**
- 設計レビューの精度向上
- オーバーライドの確認
- 継承関係の可視化

---

## 5. 成功基準

### 5.1 v0.5.1（LSP基盤）

**目標:** LSP接続基盤の構築

**成功基準:**
- ✅ LSPState Actor実装
- ✅ LSPClient実装（initialize, initialized対応）
- ✅ 動的ツールリスト生成
- ✅ バックグラウンドLSP接続

**実績:**
- ✅ 全て達成（2025-10-21）

---

### 5.2 v0.5.2（find_symbol_references）

**目標:** 型情報ベース参照検索の実現

**成功基準:**
- ✅ find_symbol_referencesツール実装
- ✅ LSP textDocument/referencesリクエスト成功
- ✅ 参照検索が動作

**実績:**
- ✅ ツール実装完了（2025-10-21）
- ⚠️ クラッシュ問題発生（3回目で終了）

---

### 5.3 v0.5.3（LSP安定化）

**目標:** find_symbol_referencesの完全動作

**成功基準:**
- ✅ LSPプロトコル完全準拠
- ✅ 5回以上連続実行でクラッシュなし
- ✅ 実際に参照を検出できる
- ✅ デバッグ環境整備

**実績:**
- ✅ 全て達成（2025-10-24）
- ✅ initialized通知、didOpen実装
- ✅ 5回連続成功、34件検出
- ✅ FileLogHandler、DebugRunner実装

---

### 5.4 v0.5.4（list_symbols/get_type_hierarchy強化）

**目標:** 既存ツールの型情報強化

**成功基準:**
- ✅ list_symbols: LSP版で型情報表示
- ✅ get_type_hierarchy: LSP版でType Detail表示
- ✅ グレースフルデグレード動作
- ✅ クラッシュなし

**評価指標:**
- 型情報表示率: 100%（LSP利用可能時）
- フォールバック成功率: 100%（LSP利用不可時）

---

### 5.5 v0.5.5（追加LSP機能）

**目標:** 呼び出し階層など

**成功基準:**
- get_call_hierarchy実装
- その他LSP機能（必要性を判断）

---

## 6. 制約と前提

### 6.1 技術的制約

**必須:**
- macOS 13.0+
- Swift 5.9+
- SwiftSyntax 602.0.0

**オプション:**
- SourceKit-LSP（LSP機能使用時）
- ビルド可能なプロジェクト（LSP機能使用時）

---

### 6.2 設計制約

**不変の原則:**
1. ビルド非依存性の維持
2. ローカル完結性
3. グレースフルデグレード

**これらは絶対に崩さない**

---

### 6.3 LSP利用の前提条件

**LSPツールが動作する条件:**
1. プロジェクトがSwift Packageである
2. ビルドが可能である（`swift build`が成功）
3. SourceKit-LSPがインストールされている

**動作しない条件:**
- Xcodeプロジェクト（.xcodeproj）のみ
- ビルドエラーあり
- SourceKit-LSP未インストール

**対策:**
- ✅ 動作しない場合はSwiftSyntax版で動作
- ✅ エラーメッセージで状況を説明

---

## 7. 想定される質問と回答

### Q1: なぜSwiftSyntaxだけじゃダメなのか？

**A:** 型情報がないため、参照検索が不正確です。

**例:**
```swift
class UserRepository {
    func save(user: User) { ... }
}

class PostRepository {
    func save(post: Post) { ... }
}

// "save"で検索すると両方ヒット（ノイズ）
// LSPなら型情報で区別できる
```

---

### Q2: なぜLSPだけじゃダメなのか？

**A:** ビルド不要の原則を崩すからです。

実装中のコード（ビルドエラーあり）でも解析できることがSwift-Selenaの最大の価値です。

---

### Q3: Xcodeでいいのでは？

**A:** XcodeはMCP統合できず、AIアシスタントと連携できません。

Claude CodeからXcodeの解析結果を取得する手段がありません。

---

### Q4: ハイブリッドは複雑では？

**A:** 確かに複雑ですが、両方の利点を得られます。

**トレードオフ:**
- 実装複雑度: 増加
- ユーザー体験: 大幅向上（ビルド不要 + 型情報）

**結論:** 複雑さを引き受ける価値がある

---

## 8. 実装優先度

### 8.1 フェーズ別優先度

#### Phase 1（v0.5.1-v0.5.3）: 最高優先 🔴

**理由:**
- LSP基盤がないと何も始まらない
- find_symbol_referencesは最も需要が高い
- 安定性は絶対条件

**実績:**
- ✅ 完了（2025-10-24）

---

#### Phase 2（v0.5.4）: 高優先 🟡

**理由:**
- list_symbols、get_type_hierarchyは使用頻度が高い
- 型情報があると理解が格段に早い
- 実装パターンが確立済み

**工数:** 1.5時間

---

#### Phase 3（v0.5.5）: 中優先 🟢

**理由:**
- get_call_hierarchyは便利だが必須ではない
- 実用で必要性を判断

**工数:** 1週間

---

### 8.2 機能別優先度

| 機能 | 優先度 | 理由 |
|------|--------|------|
| find_symbol_references | 🔴 最高 | リファクタリングで必須 |
| list_symbols強化 | 🟡 高 | コード理解で頻繁に使用 |
| get_type_hierarchy強化 | 🟡 高 | アーキテクチャ理解で重要 |
| get_call_hierarchy | 🟢 中 | あれば便利 |

---

## 9. リスクと対策

### 9.1 技術リスク

#### リスク1: SourceKit-LSP APIのサポート状況

**懸念:**
- documentSymbol, typeHierarchy が本当にサポートされているか？

**確認方法（v0.5.3で実施済み）:**
```
Initialize response の capabilities:
{
  "documentSymbolProvider": 1,  ✅ サポート済み
  "typeHierarchyProvider": 1,   ✅ サポート済み
  "referencesProvider": 1        ✅ サポート済み
}
```

**結論:** リスク低。全てサポート済み。

---

#### リスク2: レスポンス形式の不一致

**懸念:**
- 想定と異なるJSON形式が返る可能性

**対策:**
- 詳細ログでレスポンス全体を確認（v0.5.3実装済み）
- try-catchで安全にフォールバック
- DebugRunnerで事前テスト

**結論:** リスク低。ログで確認可能。

---

#### リスク3: パフォーマンス劣化

**懸念:**
- textDocument/didOpenでファイル全体を送信
- 大きなファイルで遅延の可能性

**対策:**
- openedFilesキャッシュ（同じファイルは1回のみ）
- 必要なファイルのみ開く

**結論:** リスク低。キャッシュで対策済み。

---

### 9.2 運用リスク

#### リスク4: LSP利用可能性の誤解

**懸念:**
- ユーザーが「なぜLSPツールが使えないのか」理解できない

**対策:**
- エラーメッセージで明確に説明
- 代替ツール（SwiftSyntax版）を案内

**例:**
```
❌ LSP not available.

This tool requires a buildable project with SourceKit-LSP.

💡 Alternatives:
- Use 'find_type_usages' for type-level reference search (SwiftSyntax)
- Use 'search_code' for text-based search
```

**結論:** エラーメッセージで対応済み。

---

## 10. 実装戦略

### 10.1 段階的実装の理由

**なぜ一度に全部実装しないのか？**

**理由:**
1. **リスク分散**
   - 1機能ずつテスト・検証
   - 問題があれば即座に修正

2. **学習曲線**
   - LSPプロトコルの理解を深める
   - 実装パターンを確立

3. **品質優先**
   - 動かないものを積み重ねない
   - 各バージョンで完全動作を保証

**v0.5.3での成功例:**
- initialized通知の欠落を発見・修正
- 段階的にプロトコル理解を深めた
- 結果: 安定動作達成

---

### 10.2 v0.5.4の実装方針

**確立したパターンの適用:**

```
findReferences()の成功パターンを
documentSymbol(), typeHierarchy()に適用

1. sendDidOpen()
2. リクエスト作成（Content-Length計算）
3. プロセス状態チェック
4. 送信（try-catch）
5. レスポンス受信
6. JSON解析（エラーチェック含む）
7. 結果変換
```

**新しいことはしない** = リスク低

---

## 11. 成果物と deliverables

### 11.1 v0.5.4完了時の成果物

**コード:**
- LSPClient.swift（+150行）
- ListSymbolsTool.swift（+50行）
- GetTypeHierarchyTool.swift（+40行）
- SwiftMCPServer.swift（+30行）

**ドキュメント:**
- DES-009: 詳細設計書
- REQ-002: 要件定義書（本文書）
- HISTORY.md更新

**テスト:**
- DebugRunnerテストケース追加
- 自動テスト実行ログ

---

### 11.2 提供価値

**開発者への価値:**
- ✅ 型情報付きシンボル一覧
- ✅ 正確な参照検索
- ✅ ビルド不可時も動作（グレースフルデグレード）

**AIアシスタントへの価値:**
- ✅ より正確なコード理解
- ✅ 型情報に基づく推論
- ✅ リファクタリング支援の精度向上

---

## 12. v0.5.x系の全体像

### 12.1 バージョン別の役割

```
v0.5.1: 基盤構築
  → LSPState, LSPClient
  → まだツールは使えない

v0.5.2: 最初のLSPツール
  → find_symbol_references
  → クラッシュ問題発生

v0.5.3: 安定化
  → LSPプロトコル完全準拠
  → デバッグ環境整備
  → find_symbol_references完全動作 ✅

v0.5.4: 既存ツール強化（計画中）
  → list_symbols強化
  → get_type_hierarchy強化
  → 確立したパターンの適用

v0.5.5: 追加機能（将来）
  → get_call_hierarchy
  → その他LSP機能
```

---

### 12.2 累積的な価値

**v0.5.0:**
- 22ツール、ビルド不要

**v0.5.1:**
- +LSP基盤

**v0.5.2:**
- +find_symbol_references（1ツール）

**v0.5.3:**
- +安定性、デバッグ環境

**v0.5.4:**
- +型情報強化（2ツール）

**v0.5.5:**
- +呼び出し階層（1-2ツール）

**最終:** 19-20ツール、ハイブリッド、高品質

---

## 13. 承認事項

### 13.1 要件の妥当性

**確認事項:**
1. ✅ ビルド非依存性を維持しているか
2. ✅ グレースフルデグレードを保証しているか
3. ✅ 段階的実装になっているか
4. ✅ 各バージョンで完全動作を達成しているか

### 13.2 スコープの妥当性

**確認事項:**
1. ✅ v0.5.4のスコープは適切か（2ツール強化のみ）
2. ✅ 工数見積もり（1.5時間）は妥当か
3. ✅ リスクは管理されているか

---

**この要件定義で承認いただけますか？**

**次に作成:** REQ-003（コア機能要件）
