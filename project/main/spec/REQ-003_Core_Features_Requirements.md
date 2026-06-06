# REQ-003: Swift-Selena コア機能要件定義

**要件ID**: REQ-003
**作成日**: 2025-10-24
**対象**: 全18ツール（v0.5.3時点）
**ステータス**: 承認待ち
**関連文書**: REQ-001, REQ-002, CLAUDE.md / 設計: DES-104（search_code・find_symbol_definition 強化の詳細設計）

---

> ℹ️ **旧 REQ-005（improve feature「検索・シンボルツール強化」）の統合について**: REQ-005 は v0.6.8 で実装完了し、その要件は本 REQ-003（§2.2 search_code / §2.3 find_symbol_definition）へ統合のうえ削除された（improve → main の spec マージ）。本書中の「REQ-005 §X.X」参照は統合元の要件節を指す歴史的トレーサビリティ記録であり、設計詳細は DES-104 が対応する。

---

## 1. ツール全体像

### 1.1 ツール分類

Swift-Selenaは**18個のツール**を提供（v0.5.3時点）

**カテゴリ別:**
```
プロジェクト管理: 1ツール
ファイル検索: 2ツール
シンボル解析: 3ツール
SwiftUI解析: 3ツール
依存関係解析: 4ツール
効率的読み取り: 1ツール
分析モード: 2ツール
プロジェクトノート: 2ツール
LSP機能: 1ツール（条件付き）
```

---

### 1.2 動作モード別

**常時利用可能（17ツール）:**
- ビルド不要
- SwiftSyntaxベース
- どんなプロジェクトでも動作

**条件付き利用（1ツール）:**
- ビルド可能時のみ
- LSPベース
- find_symbol_references（⚠️ v0.5.3 時点の記述。2025-10-27 `commit f0a547f` で削除済み。§2.9 参照）

---

## 2. カテゴリ別要件

### 2.1 プロジェクト管理

#### initialize_project

**要件:**
プロジェクトを初期化し、ProjectMemoryを作成する

**なぜ必要か:**
- 全ツールの前提条件
- プロジェクトパスの設定
- キャッシュの初期化
- LSP接続の試行（v0.5.1+）

**入力:**
- `project_path`: プロジェクトルートのパス

**出力:**
```
✅ Project initialized: /path/to/project

ℹ️ Checking LSP availability in background...

📊 プロジェクト統計
プロジェクト名: MyApp
最終解析: 2025/10/24 10:00
インデックス済みファイル: 0
キャッシュ済みシンボル: 0
保存されたメモ: 0
```

**受入基準:**
- ✅ ProjectMemory作成成功
- ✅ ディレクトリ作成（~/.swift-selena/clients/...）
- ✅ LSP接続試行（バックグラウンド、非ブロッキング）

**ユースケース:**
```
全てのツール使用前に必ず実行:

initialize_project("/Users/me/MyApp")
→ プロジェクト初期化
→ 以降、他のツールが使用可能
```

---

### 2.2 ファイル検索

#### find_files

**要件:**
ワイルドカードパターンでファイルを高速検索

**なぜ必要か:**
- プロジェクト内のファイルを素早く発見
- 命名規則ベースの検索（*ViewModel.swift等）
- grepより高速

**入力:**
- `pattern`: ワイルドカードパターン（`*Controller.swift`）

**出力:**
```
Found 23 files matching '*Controller.swift':

  App/ViewController.swift
  App/LoginController.swift
  ...
```

**受入基準:**
- ✅ ワイルドカード（*, ?）対応
- ✅ NSRegularExpressionで実装
- ✅ 1000ファイルプロジェクトで1秒以内

**ユースケース:**
```
UC: 全ViewControllerを見つける
  → find_files("*ViewController.swift")
  → 15個のViewControllerファイルを発見

UC: テストファイルを列挙
  → find_files("*Tests.swift")
  → 全テストファイルを取得
```

---

#### search_code

**要件:**
正規表現でコード内容を検索（grep的）。結果量が膨大化する場合に備え、**出力モード**と**件数上限**で結果を制御でき、テキスト出力に加え**構造化結果**を併記する（v0.6.8、REQ-005 §4.1 / §4.2）

**なぜ必要か:**
- 特定の関数呼び出しを検索
- パターンマッチング
- コメント検索
- 巨大プロジェクトで一般語を検索する際の結果量制御（「どのファイルにあるか」だけ知りたいケースに対応）
- 呼び出し側（AI/Agent）がテキストパースなしで結果を加工できる構造化データの提供

**入力:**
- `pattern`: 正規表現
- `include_patterns`: 対象に含める glob 配列（オプション、最大 20 件）
- `exclude_patterns`: 対象から除外する glob 配列（オプション、最大 20 件、include に勝つ）
- `output_mode`: 出力モード（`match_detail`（既定・後方互換、ファイル/行番号/該当行）/ `file_list`（マッチを含むファイル一覧、重複排除）/ `count_only`（マッチ数とファイル数））（v0.6.8、REQ-005 §4.1）
- `limit`: 件数上限（1〜10,000 の整数。超過分は切り詰め、省略があった旨を通知。`count_only` では対象外）（v0.6.8、REQ-005 §4.1）

> v0.6.8 (REQ-005 / DES-104 §5.1) で `file_pattern` 単独パラメータを廃止し、`search_files_without_pattern` と共通の `include_patterns` / `exclude_patterns` 配列に統一した。

**出力:**
```
Found 12 matches:

  UserManager.swift:15: func createUser
  UserRepository.swift:28: func createUser
  ...

--- structured ---
{ "matches": [ { "file": "...", "line": 15, "content": "func createUser" }, ... ],
  "total": 12, "truncated": false }
```
人間可読テキスト（既存の行頭フォーマット `<file>:<line>: <content>` を維持）の末尾に、フィールド名で識別可能な構造化結果（`--- structured ---` JSON ブロック）を併記する（v0.6.8、REQ-005 §4.2）

**受入基準:**
- ✅ 正規表現対応
- ✅ ファイルフィルタ対応（include / exclude patterns）
- ✅ grep並みの速度
- ✅ 出力モード（`match_detail` / `file_list` / `count_only`）を選択でき、既定は `match_detail`（後方互換）（v0.6.8）
- ✅ 件数上限を 1〜10,000 で指定でき、超過時はテキスト・構造化結果の双方で省略を明示（v0.6.8）
- ✅ テキスト出力の末尾に構造化結果（`--- structured ---` JSON、ファイルパス・行番号・マッチ行内容・総数・省略フラグ）を併記（v0.6.8）
- ✅ 正規表現・glob の構文エラーは原因と修正案を含むエラーメッセージで明示（v0.6.8、REQ-005 §4.8）

**ユースケース:**
```
UC: TODO コメント検索
  → search_code("// TODO")
  → 全TODOコメントを発見

UC: 本実装のみ検索（テスト・モック除外）
  → search_code("URLSession\\.shared",
                include_patterns: ["Sources/**/*.swift"], exclude_patterns: ["*Tests*"])

UC: どのファイルにあるかだけ知りたい
  → search_code("func createUser", output_mode: "file_list")

UC: 件数だけ把握したい
  → search_code("import", output_mode: "count_only")
```

---

### 2.3 シンボル解析

#### list_symbols

**要件:**
ファイル内の全シンボル（Class, Function等）を列挙

**なぜ必要か:**
- ファイルの構造を素早く把握
- AIがコードを理解する第一歩
- 「このファイルに何がある？」に答える

**入力:**
- `file_path`: Swiftファイルのパス

**出力（SwiftSyntax版）:**
```
Symbols in UserManager.swift:

[Class] UserManager (line 10)
[Variable] repository (line 12)
[Function] createUser (line 20)
[Function] deleteUser (line 35)
```

**出力（LSP版、v0.5.4+）:**
```
Symbols in UserManager.swift (LSP enhanced):

[Class] UserManager: class UserManager (line 10)
[Property] repository: let repository: UserRepositoryProtocol (line 12)
[Method] createUser: func createUser(name: String) async throws -> User (line 20)
[Method] deleteUser: func deleteUser(id: Int) async throws (line 35)
```

**受入基準:**
- ✅ Class, Struct, Enum, Protocol, Function, Variable全て検出
- ✅ 正確な行番号
- ✅ v0.5.4: LSP版で型情報表示

**ユースケース:**
```
UC: 初めて見るファイルの理解
  開発者: 「このファイルに何がある？」
  Claude: list_symbols("SomeFile.swift")
  Claude: 「3つのクラスと5つの関数があります...」
  → 30秒で構造把握

UC: リファクタリング前の確認
  開発者: 「OldUserManagerに何がある？」
  list_symbols("OldUserManager.swift")
  → メソッド一覧を確認してから移行開始
```

---

#### find_symbol_definition

**要件:**
プロジェクト全体でシンボル定義を検索。同名シンボルが複数存在する場合に、**種別フィルタ**と**所属スコープ情報**で絞り込み・識別でき、構造化結果も併記する（v0.6.8、REQ-005 §4.4 / §4.2）

**なぜ必要か:**
- 「UserManagerクラスはどのファイル？」に答える
- 定義箇所を特定
- 複数ファイルにまたがる検索
- 同名シンボルが異なるスコープ（ネスト型・extension・別モジュール）に複数存在する場合の判別

**入力:**
- `symbol_name`: シンボル名（例: "UserManager"）
- `symbol_kinds`: シンボル種別フィルタ配列（オプション、最大 9 件、OR 結合）。`struct` / `class` / `enum` / `protocol` / `actor` / `function` / `variable` / `typealias` / `extension` の小文字スネーク 9 区分（v0.6.8、REQ-005 §4.4.1）

**出力:**
```
Found 2 definitions for 'UserManager':

  Domain/UserManager.swift:10 [Class]  (module: MyApp)
  Tests/MockUserManager.swift:5 [Class]

--- structured ---
{ "definitions": [
    { "file": "...", "line": 10, "kind": "class",
      "parent_scope": null, "extension_target": null, "module_name": "MyApp" }, ... ] }
```
所属スコープ情報（**親スコープ名** / **extension 対象型** / **モジュール名**）を付与し、ルート定義・ネスト型・extension 由来の同名シンボルを区別できる。テキスト出力の末尾に構造化結果（`--- structured ---` JSON）を併記する（v0.6.8、REQ-005 §4.4.2 / §4.2）

**受入基準:**
- ✅ プロジェクト全体を検索
- ✅ キャッシュで高速化
- ✅ 複数定義を全て発見
- ✅ Class/Struct/Enum/Protocol/Actor の定義を優先して返す（v0.6.5+）
- ✅ 複数候補がある場合は全候補を返す
- ✅ シンボルが見つからない場合は「検索ファイル数・考えられる原因」を含むメッセージを返す（v0.6.5+）
- ✅ `symbol_kinds` を配列で指定でき、指定種別のいずれかに合致する定義を OR 結合で返す。未指定時は全 9 区分（v0.6.8、REQ-005 §4.4.1）
- ✅ 配列に未定義の種別文字列が含まれる場合は入力エラーで明示（部分的無視は行わない）（v0.6.8）
- ✅ 結果に所属スコープ情報（親スコープ名・extension 対象型・モジュール名）を付与し、ルート定義 / ネスト型 / extension 由来の同名シンボルを区別可能（v0.6.8、REQ-005 §4.4.2）
- ✅ テキスト出力の末尾に構造化結果（`--- structured ---` JSON）を併記（v0.6.8、REQ-005 §4.2）

**エラー時の挙動（v0.6.5+）:**
- シンボルが見つからない場合、以下を含むメッセージを返す:
  - 検索したファイル数
  - 考えられる原因（スペルミス / 外部パッケージ定義 / 存在しない）
- プロジェクト未初期化: `initialize_project` の案内を含むエラー
- `symbol_kinds` に未定義の種別が含まれる場合: 原因と有効な 9 区分を含む入力エラー（v0.6.8）

**ユースケース:**
```
UC: クラス定義の発見
  開発者: 「UserRepositoryProtocolはどこ？」
  find_symbol_definition("UserRepositoryProtocol")
  → Domain/Protocol/UserRepositoryProtocol.swift:12

UC: 重複定義の検出
  find_symbol_definition("Config")
  → 2つの定義を発見（本番用とテスト用）

UC: シンボルが見つからない場合（v0.6.5+）
  find_symbol_definition("NonExistent")
  → "Symbol not found. Searched 42 files.
     Possible causes: typo / defined in external package"
```

---

#### find_references

> ⚠️ **未実装**（2026-05 時点）。本ツールは仕様として記述されたが、実装されたことがない（REQ-005 §6.1 / §6.3）。LSP 系参照検索ツールの再導入可否は別途独立 Feature として検討する。以下は当時の仕様記述を歴史的記録として保持する。

**要件:**
シンボルの参照箇所をプロジェクト全体から検索（LSP不要）

**なぜ必要か:**
- LSP利用不可環境でも参照検索が必要
- `find_symbol_references`（LSP版）の代替（テキストベース）
- 単語境界を考慮した精度の高い検索

**入力:**
- `symbol_name`: シンボル名（例: "UserManager"）

**単語境界の定義:**
シンボルの前後が行頭/行末・空白・記号（`()[]{}.,;:<>!=+-*/&|^~?@#$%`）の場合にマッチ
- ✅ マッチ: `User.name`, `let user: User`, `(User)`
- ❌ 非マッチ: `UserName`, `AppUser`, `userId`

**出力:**
```
Found 15 references to 'User':

  UserManager.swift:20 - let user: User
  UserRepository.swift:15 - func save(_ user: User) async throws
  ProfileView.swift:18 - @State private var user: User
  ...

Total: 15 references in 8 files
```

**受入基準:**
- ✅ 単語境界を考慮した検索（部分一致を除外）
- ✅ ファイルパス・行番号・該当行の内容を返す
- ✅ 参照が見つからない場合は空のリストを返す（エラーではない）
- ✅ プロジェクト未初期化: `initialize_project` の案内

**制限事項:**
- テキストベース検索のため、LSPほど正確ではない（同名の異なるシンボルを区別できない）

**ユースケース:**
```
UC: LSP無効環境でのリファクタリング影響確認
  開発者: 「User型がどこで使われてる？」
  find_references("User")
  → 15箇所を発見（LSP不要）

UC: find_symbol_references との使い分け
  ビルド可能時: find_symbol_references（型情報ベース、正確）
  ビルド不可時: find_references（テキストベース、LSP不要）
```

---

#### read_symbol

**要件:**
特定シンボル（関数、クラス等）のコードのみを読み取り

**なぜ必要か:**
- ファイル全体を読むとコンテキスト消費が大きい
- 特定関数の実装だけ見たい
- 大規模ファイル（5000行+）での効率化

**入力:**
- `file_path`: ファイルパス
- `symbol_path`: シンボルパス（例: "UserManager/createUser"）

**出力:**
```
[Method] createUser
Location: UserManager.swift:20-35

```swift
func createUser(name: String) async throws -> User {
    guard !name.isEmpty else {
        throw UserError.invalidName
    }

    let user = User(name: name)
    try await repository.save(user)
    return user
}
```
```

**受入基準:**
- ✅ シンボル単位で抽出
- ✅ ネストしたシンボル対応（Class/method）
- ✅ 大規模ファイルで効率化

**ユースケース:**
```
UC: 特定メソッドの実装確認
  開発者: 「createUserメソッドの実装を見せて」
  read_symbol("UserManager.swift", "UserManager/createUser")
  → メソッドのみ表示（ファイル全体は読まない）

UC: コンテキスト節約
  5000行のファイルで1つのメソッドだけ見たい
  → read_symbol使用で95%のコンテキスト節約
```

---

### 2.4 SwiftUI解析

#### list_property_wrappers

**要件:**
SwiftUI Property Wrapper（@State, @Binding等）を検出

**なぜ必要か:**
- SwiftUIの状態管理を理解
- @State, @Binding, @StateObject, @ObservedObject, @EnvironmentObjectの区別
- AIがSwiftUIコードを正しく理解

**入力:**
- `file_path`: SwiftUIビューのファイル

**出力:**
```
Property Wrappers in ContentView.swift:

@State: counter (type: Int, line: 15)
@Binding: isPresented (type: Bool, line: 16)
@StateObject: viewModel (type: ContentViewModel, line: 17)
@ObservedObject: settings (type: Settings, line: 18)
@EnvironmentObject: appState (type: AppState, line: 19)
```

**受入基準:**
- ✅ 全Property Wrapper検出（@State, @Binding, @StateObject, @ObservedObject, @EnvironmentObject, @Environment等）
- ✅ プロパティ名、型名、行番号を抽出
- ✅ SwiftSyntax Visitorで実装

**ユースケース:**
```
UC: SwiftUIビューの状態管理理解
  開発者: 「このビューの状態はどうなってる？」
  list_property_wrappers("ProfileView.swift")

  結果:
  @State name: String  ← ローカル状態
  @Binding isPresented: Bool  ← 親から注入
  @StateObject viewModel: ProfileViewModel  ← ViewModelの所有

  → 状態管理フローを完全に把握

UC: リファクタリング時の依存確認
  @EnvironmentObjectを使っているビューを全て見つける
  → 影響範囲を把握
```

---

#### list_protocol_conformances

**要件:**
Protocol準拠と継承関係を解析

**なぜ必要か:**
- クラスがどのProtocolを実装しているか
- どのクラスを継承しているか
- アーキテクチャの理解

**入力:**
- `file_path`: Swiftファイル

**出力:**
```
Protocol Conformances in ViewController.swift:

[Class] ViewController (line: 10)
  Type: Class
  Superclass: UIViewController
  Protocols: UITableViewDelegate, UITableViewDataSource

[Struct] UserData (line: 50)
  Type: Struct
  Protocols: Codable, Equatable
```

**受入基準:**
- ✅ スーパークラス検出
- ✅ Protocol準拠検出
- ✅ Class/Struct/Enum全対応

**ユースケース:**
```
UC: Protocolの実装状況確認
  開発者: 「RepositoryProtocolを実装しているクラスは？」
  → 各ファイルでlist_protocol_conformancesを実行
  → 実装クラスを発見

UC: 継承階層の確認
  開発者: 「このクラスは何を継承してる？」
  → スーパークラスを即座に確認
```

---

#### list_extensions

**要件:**
Extension（拡張）を解析

**なぜ必要か:**
- Extensionでどのメソッドが追加されているか
- Protocol準拠がExtensionで実装されているか
- コードの構造理解

**入力:**
- `file_path`: Swiftファイル

**出力:**
```
Extensions in String+Ext.swift:

Extension: String (line: 10)
  Conforms to: CustomStringConvertible
  Members:
    - [Function] trimmed (line: 12)
    - [Function] isValidEmail (line: 18)

Extension: String (line: 30)
  Members:
    - [Function] toInt (line: 32)
```

**受入基準:**
- ✅ 拡張対象の型を検出
- ✅ Protocol準拠（Extension内）を検出
- ✅ Extensionのメンバーを列挙

**ユースケース:**
```
UC: Stringの拡張メソッド確認
  開発者: 「Stringに何のメソッドを追加してる？」
  list_extensions("String+Ext.swift")
  → trimmed(), isValidEmail(), toInt() を発見

UC: Protocol準拠の実装場所
  開発者: 「EquatableはどこでExtensionしてる？」
  → Extension内のProtocol準拠を発見
```

---

### 2.5 依存関係解析

#### analyze_imports

**要件:**
プロジェクト全体のImport依存関係を解析

**なぜ必要か:**
- どのモジュールが使われているか
- 依存関係の把握
- アーキテクチャの理解

**入力:**
なし（プロジェクト全体を解析）

**出力:**
```
Import Analysis:

Most used modules:
  1. Foundation: 85 files
  2. SwiftUI: 42 files
  3. Combine: 28 files
  4. XCTest: 15 files

Total imports: 170
Unique modules: 12
```

**受入基準:**
- ✅ 全Swiftファイルを走査
- ✅ モジュール使用頻度を集計
- ✅ キャッシュで2回目以降高速化

**ユースケース:**
```
UC: 使用モジュールの把握
  アーキテクト: 「どのフレームワークを使ってる？」
  analyze_imports()
  → Foundation, SwiftUI, Combineが主要モジュール

UC: 不要な依存の検出
  analyze_imports()
  → Alamofireが1ファイルのみ
  → 削除候補として検討
```

---

#### get_type_hierarchy

**要件:**
型の継承階層を取得

**なぜ必要か:**
- クラス階層の可視化
- スーパークラス・サブクラスの把握
- Protocol実装の確認

**入力:**
- `type_name`: 型名（例: "UserViewController"）

**出力（SwiftSyntax版）:**
```
Type Hierarchy for 'UserViewController':

[Class] UserViewController
  Location: UserViewController.swift:15

Inherits from:
  └─ BaseViewController

Conforms to:
  └─ UITableViewDelegate
  └─ UITableViewDataSource

Subclasses:
  └─ AdminUserViewController
```

**出力（LSP版、v0.5.4+）:**
```
Type Hierarchy for 'UserViewController' (LSP enhanced):

[Class] UserViewController
  Location: UserViewController.swift:15
  Type Detail: class UserViewController: BaseViewController

Inherits from:
  └─ BaseViewController

Conforms to:
  └─ UITableViewDelegate
  └─ UITableViewDataSource
```

**受入基準:**
- ✅ スーパークラス検出
- ✅ サブクラス検出（プロジェクト全体から）
- ✅ Protocol準拠検出
- ✅ v0.5.4: LSP版でType Detail追加
- ✅ v0.6.5+: ツール実行時にプロジェクト内の全Swiftファイルを再スキャンして最新の型情報を取得する
- ✅ v0.6.5+: 型が見つからない場合、以下を含むメッセージを返す:
  - 検索したファイル数
  - 検出可能な型の総数
  - 考えられる原因（スペルミス / 外部パッケージ定義 / 存在しない）

**検出対象（v0.6.5+）:**
- プロジェクトディレクトリ配下のSwiftファイルで定義された型（Class/Struct/Enum/Protocol/Actor）
- 除外: `.build/`, `.git/`, `DerivedData/`, `Pods/`, `Carthage/` 配下

**ユースケース:**
```
UC: 継承階層の可視化
  開発者: 「BaseViewControllerを継承しているクラスは？」
  get_type_hierarchy("BaseViewController")
  → 5つのサブクラスを発見

UC: Protocol実装の確認
  get_type_hierarchy("UserRepositoryProtocol")
  → Protocolを実装している型を列挙

UC: 型が見つからない場合（v0.6.5+）
  get_type_hierarchy("NonExistent")
  → "Type not found. Searched 42 files, 87 types detected.
     Possible causes: typo / defined in external package"
```

---

#### find_test_cases

**要件:**
XCTestケースとテストメソッドを検出

**なぜ必要か:**
- テストカバレッジの把握
- どのテストが存在するか
- テスト戦略の理解

**入力:**
なし（プロジェクト全体を検索）

**出力:**
```
XCTest Cases Found:

UserManagerTests (UserManagerTests.swift:10)
  - testCreateUser (line: 15)
  - testDeleteUser (line: 25)
  - testUpdateUser (line: 35)

UserRepositoryTests (UserRepositoryTests.swift:8)
  - testSave (line: 12)
  - testFind (line: 20)

Total: 2 test classes, 5 test methods
```

**受入基準:**
- ✅ XCTestCase継承クラスを全て検出
- ✅ test*メソッドを全て列挙
- ✅ 行番号を正確に取得

**ユースケース:**
```
UC: テストカバレッジ確認
  QA: 「UserManagerのテストはある？」
  find_test_cases()
  → UserManagerTests が存在
  → 3つのテストメソッドを確認

UC: テスト追加の計画
  find_test_cases()
  → 既存テストを把握
  → 不足しているテストを特定
```

---

#### analyze_file_metrics

**要件:**
プロジェクト内のSwiftファイルの行数・サイズを取得し、リファクタリング候補を検出する

**なぜ必要か:**
- 大きすぎるファイルを特定してリファクタリング対象を発見
- 行数・サイズ順でソートして優先順位付け
- コード品質の定量的把握

**入力:**
- `file_path` (optional): 単一ファイル指定
- `pattern` (optional): ファイルパターン（例: "*.swift"）
- `threshold_lines` (optional): 行数しきい値（デフォルト: 500）
- `sort_by` (optional): ソート基準（`"lines"` | `"size"`、デフォルト: `"lines"`）
- `limit` (optional): 結果数制限（デフォルト: 20）

**出力:**
```
File Metrics (sorted by lines, threshold: 500):

Files exceeding threshold (3 files):
  SwiftSyntaxAnalyzer.swift: 580 lines (24.3 KB)
  LSPClient.swift:           552 lines (21.8 KB)
  ProjectMemory.swift:       510 lines (18.2 KB)

Summary:
  Total files: 42
  Total lines: 8,420
  Files over threshold: 3 (7.1%)
```

**受入基準:**
- ✅ 正確な行数を返す（空行・コメント行含む）
- ✅ 行数しきい値でフィルタリング
- ✅ lines / size でソート可能
- ✅ 結果数を制限可能
- ✅ プロジェクト未初期化: `initialize_project` の案内

**パフォーマンス:**
- 340ファイルで1秒以内

**ユースケース:**
```
UC: リファクタリング候補の検出
  analyze_file_metrics(threshold_lines: 500)
  → 500行超のファイルを列挙 → 分割候補を把握

UC: 最大ファイルの確認
  analyze_file_metrics(sort_by: "lines", limit: 5)
  → 行数上位5ファイルを取得
```

---

#### find_type_usages

> ⚠️ **削除済み**（2025-12-06 `commit 580b1f7`「不要な分析機能を削除」、REQ-005 §6.3）。以下は削除前の仕様記述を歴史的記録として保持する。

**要件:**
型の使用箇所を検出

**なぜ必要か:**
- リファクタリング影響範囲の確認
- 型がどこで使われているか
- LSP版（find_symbol_references）の代替（ビルド不可時）

**入力:**
- `type_name`: 型名（例: "User"）

**出力:**
```
Type 'User' is used in:

  UserManager.swift:20 - Function parameter
  UserRepository.swift:15 - Function return type
  ProfileView.swift:18 - Variable declaration
  ...

Total: 15 usages
```

**受入基準:**
- ✅ 変数宣言での使用検出
- ✅ 関数パラメータでの使用検出
- ✅ 戻り値型での使用検出

**ユースケース:**
```
UC: リファクタリング影響確認（ビルド不可時）
  開発者: 「User型を変更したい、どこで使ってる？」
  find_type_usages("User")
  → 15箇所で使用（型レベル）

UC: LSP版との使い分け
  ビルド可能時: find_symbol_references（メソッドレベル、正確）
  ビルド不可時: find_type_usages（型レベル、おおまか）
```

---

### 2.6 効率的読み取り

#### read_symbol

**（既に2.3で説明済み）**

---

### 2.7 分析モード

#### set_analysis_mode

**要件:**
分析モードを設定し、ツール使用ガイダンスを提供

**なぜ必要か:**
- 目的に応じた推奨ツールを案内
- SwiftUI解析、アーキテクチャ解析等でツールが異なる
- 初心者への支援

**入力:**
- `mode`: SwiftUI / Architecture / Testing / Refactoring / General

**出力:**
```
Analysis mode set to: SwiftUI

推奨ツール:
- list_property_wrappers: SwiftUI状態管理の把握
- list_protocol_conformances: View Protocolの確認
- find_type_usages: @Stateプロパティの使用箇所

分析のポイント:
- Property Wrapperに注目
- 状態のフローを追う
```

**受入基準:**
- ✅ 5つのモード対応
- ✅ モード別推奨ツール表示
- ✅ 分析ポイント提示

**ユースケース:**
```
UC: SwiftUI開発支援
  set_analysis_mode("SwiftUI")
  → SwiftUI特化のツール使用ガイド表示

UC: テスト分析
  set_analysis_mode("Testing")
  → find_test_cases, test coverageに関する推奨表示
```

---

#### think_about_analysis

**要件:**
収集した情報について振り返りを促す

**なぜ必要か:**
- 情報を集めすぎた時の整理
- 次のステップの検討
- AIの思考プロセス改善

**入力:**
なし

**出力:**
```
🤔 分析の振り返り

収集した情報:
- 15個のシンボルを調査
- 3つのファイルを解析

次のステップ候補:
- 依存関係を確認（analyze_imports）
- テストカバレッジを確認（find_test_cases）
- 具体的な実装を読む（read_symbol）
```

**受入基準:**
- ✅ ProjectMemoryから情報取得
- ✅ 次のステップを提案

---

### 2.8 プロジェクトノート

#### add_note

**要件:**
設計決定、重要事項をメモとして永続化

**なぜ必要か:**
- セッション間で知見を共有
- 設計判断の記録
- プロジェクト固有の情報を保存

**入力:**
- `content`: メモ内容
- `tags`: タグ（オプション）

**出力:**
```
✅ Note added with tags: architecture, decision

Content: UserManagerはSingletonパターンを使用。
理由: 複数インスタンスを防ぐため。
```

**受入基準:**
- ✅ JSON形式で永続化（memory.json）
- ✅ タイムスタンプ付き
- ✅ タグ付け可能

**ユースケース:**
```
UC: 設計決定の記録
  add_note(
    content: "認証はFirebase Authを使用。理由: 実装コスト削減",
    tags: ["architecture", "auth"]
  )
  → 後で検索可能

UC: バグ調査メモ
  add_note(
    content: "UserManager.createUserでメモリリーク発見。原因調査中",
    tags: ["bug", "memory"]
  )
```

---

#### search_notes

**要件:**
保存したメモを検索

**入力:**
- `query`: 検索クエリ

**出力:**
```
Found 2 notes matching 'auth':

[2025-10-20 10:30] Tags: architecture, auth
認証はFirebase Authを使用。理由: 実装コスト削減

[2025-10-22 14:15] Tags: auth, security
OAuth実装時の注意: リフレッシュトークンの保存場所
```

**受入基準:**
- ✅ 内容とタグで検索
- ✅ タイムスタンプ順で表示

---

### 2.9 LSP機能

#### find_symbol_references

> ⚠️ **削除済み**（2025-10-27 `commit f0a547f`「find_symbol_referencesを削除」、REQ-005 §6.3）。以下は削除前の仕様サマリを歴史的記録として保持する。LSP 系参照検索ツールの再導入可否は別途独立 Feature として検討する。

**（REQ-002で詳細説明済み）**

**要件サマリ:**
- 型情報ベースの正確な参照検索
- textDocument/referencesリクエスト使用
- v0.5.2で実装、v0.5.3で完全動作達成

---

## 3. ツール間の関係

### 3.1 典型的なワークフロー

#### ワークフロー1: 初めてのプロジェクト理解

```
Step 1: プロジェクト初期化
  initialize_project("/path/to/project")

Step 2: 全体構造把握
  find_files("*.swift")
  → 全Swiftファイル一覧

Step 3: 主要ファイルの解析
  list_symbols("UserManager.swift")
  → クラス・メソッド一覧

Step 4: 依存関係確認
  analyze_imports()
  → 使用モジュール把握

Step 5: 詳細確認
  read_symbol("UserManager.swift", "UserManager/createUser")
  → 特定メソッドの実装確認
```

---

#### ワークフロー2: リファクタリング

> ⚠️ 旧ワークフローは削除済みツール（`find_symbol_references` / `find_type_usages`）を前提としていた。現在は `search_code`（テキストベースの参照検索）と `find_symbol_definition`（定義・所属スコープ確認）で代替する。

```
Step 1: 参照箇所の確認
  search_code("UserManager", output_mode: "file_list")
  → UserManager を参照するファイル一覧

Step 2: 定義の確認
  find_symbol_definition("UserManager", symbol_kinds: ["class"])
  → 定義箇所と所属スコープ情報

Step 3: テスト確認
  find_test_cases()
  → UserManagerTests の存在確認

Step 4: リファクタリング実施
  （コード変更）

Step 5: メモ記録
  add_note("UserManager リファクタリング完了", tags: ["refactoring"])
```

---

#### ワークフロー3: SwiftUI開発

```
Step 1: ビューの状態管理確認
  list_property_wrappers("ContentView.swift")
  → @State, @Binding等を列挙

Step 2: Protocol準拠確認
  list_protocol_conformances("ContentView.swift")
  → View Protocolの実装確認

Step 3: メソッド確認（LSP版）
  list_symbols("ContentView.swift")  # v0.5.4+
  → body変数の型まで表示
```

---

### 3.2 ツール選択ガイド

| 目的 | ビルド可能時 | ビルド不可時 |
|------|-------------|-------------|
| ファイル検索 | find_files | find_files |
| コード検索 | search_code | search_code |
| シンボル一覧 | list_symbols（LSP版）| list_symbols（SwiftSyntax版）|
| 参照検索 | find_symbol_references（削除済み・§2.9）| search_code（テキスト参照検索）。find_type_usages は削除済み（§2.5）|
| 型階層 | get_type_hierarchy（LSP版）| get_type_hierarchy（SwiftSyntax版）|
| SwiftUI状態 | list_property_wrappers | list_property_wrappers |

---

## 4. 成功基準

### 4.1 ツール別成功基準

| ツール | 検出率 | 速度 | 備考 |
|--------|--------|------|------|
| find_files | 100% | <1秒 | ✅ v0.5.3達成 |
| search_code | 100% | <2秒 | ✅ v0.5.3達成 |
| list_symbols | 100% | <1秒 | ✅ v0.5.3達成 |
| list_property_wrappers | 100% | <1秒 | ✅ v0.5.3達成 |
| list_protocol_conformances | 100% | <1秒 | ✅ v0.5.3達成 |
| list_extensions | 100% | <1秒 | ✅ v0.5.3達成 |
| find_symbol_references | 95%+ | <2秒 | ⚠️ 削除済み（f0a547f、§2.9）|
| get_type_hierarchy | 100% | 初回<5秒 / 2回目<500ms | v0.6.5目標 |
| find_symbol_definition | 100% | <500ms | v0.6.5目標 |
| find_references | - | - | ⚠️ 未実装（§2.3）|
| analyze_file_metrics | 100% | <1秒（340ファイル） | v0.6.5新規 |

---

### 4.2 統合成功基準

**全ツール:**
- ✅ クラッシュ率0%
- ✅ エラーメッセージが明確
- ✅ 代替ツールを案内

**LSPツール:**
- ✅ LSP利用不可時にSwiftSyntax版で動作
- ✅ エラーで終わらない

---

## 5. 制約条件

### 5.1 SwiftSyntaxツールの制約

**できること:**
- ✅ 構文が正しければ解析可能
- ✅ シンボルの種類・名前・位置を取得

**できないこと:**
- ❌ 型推論
- ❌ 型情報取得
- ❌ 正確な参照検索（文字列ベース）

---

### 5.2 LSPツールの制約

**できること:**
- ✅ 型情報完全
- ✅ 型推論
- ✅ 正確な参照検索

**できないこと（前提条件）:**
- ❌ ビルド不可のプロジェクトでは動作しない
- ❌ Xcodeプロジェクトでは動作しない可能性
- ❌ SourceKit-LSP未インストールでは動作しない

---

## 6. 将来の拡張

### 6.1 v0.6.0以降

**Code Header DB:**
- search_code_headers: 意図ベース検索
- 「ユーザー登録」で検索 → 関連コードを発見

**コメント検索:**
- search_comments: TODO/FIXME検索
- ドキュメントコメント解析

**統計:**
- get_tool_usage_stats: ツール使用統計（v0.8.0、設計見直し後）

---

## 7. 承認事項

### 7.1 要件の完全性

**確認:**
- ✅ 全18ツールの要件を定義
- ✅ なぜ必要か明確
- ✅ 使用例を提示
- ✅ 成功基準を設定

### 7.2 ツール設計の妥当性

**確認:**
- ✅ SwiftSyntax版は保持（ビルド非依存性）
- ✅ LSP版はオプション強化
- ✅ グレースフルデグレード保証

---

**この要件定義で承認いただけますか？**

**作成完了:**
- REQ-001: Swift-Selena全体要件
- REQ-002: v0.5.x LSP統合要件
- REQ-003: コア機能要件（本文書）

**次:** 全要件定義書のレビューと改善
