# 開発におけるAgent / MCPの活用

**特にリファクタリング時は全セクションを必ず確認すること**

## 目的

- 既存コード検索による重複防止
- リファクタリング時の影響範囲調査と変更漏れ防止
- アーキテクチャ検証とレイヤー違反検出
- コード理解の効率化と知見の蓄積

## 既存コード検索の基本方針 [MANDATORY]

**常に既存コード確認が最優先**。新規実装前に必ずTools/Library/を検索し、重複を防ぐ。

### コードを実装する前に

#### Swift-Selena MCP接続時（推奨・高速）

**効率化できること**（接続確認: `claude mcp list`でselena確認）:

- **実装前の重複チェック**: 類似コード・既存実装の検索
- **リファクタリング**: 型・シンボルの全使用箇所検索、影響範囲確認
- **アーキテクチャ検証**: プロトコル準拠、レイヤー間依存、Extension確認
- **効率的なコード理解**: ファイル・シンボル単位での読み込み、階層構造把握
- **知見の蓄積**: 仕様・設計のメモ保存と検索

**使い方**: 最初に`initialize_project`を実行、その後は必要に応じて各種ツールを使用

### Swift-Selena未接続時の代替手段

**直接検索**:
- **Grep**: `Grep("キーワード", path="Tools")` - Tools/Library内容検索
- **Glob**: `Glob("Tools/**/*.swift")` - ファイル検索
- **Read**: ファイル内容確認

**検索例**:
```
# 電話番号処理を探す
Grep("PhoneNumber", path="Tools")
Grep("phone.*format", path="Library")
```

## Swift-Selena MCP活用パターン [MANDATORY]

### 実装前の確認（必須）
- **類似実装検索**: `search_code` - 既存パターン確認
- **型の影響範囲**: `find_type_usages` - リファクタリング影響把握
- **シンボル一覧**: `list_symbols` - メソッド・プロパティ一覧
- **プロトコル準拠**: `list_protocol_conformances` - Entity検証
- **依存関係**: `analyze_imports` - レイヤー違反検出

### 主要ユースケース

#### 新規実装時
- **Service**: `search_code`で既存Service → `list_symbols`でメソッド確認 → `find_type_usages`でFactory登録漏れ防止
- **Entity**: `list_protocol_conformances`で必須プロトコル確認（Sendable等5つ） → `find_type_usages`で使用箇所確認
- **ViewModel**: `search_code`で@MainActor @Observable → `list_property_wrappers`で誤用チェック（0件が正常） → `find_type_usages`でSharedData連携パターン

#### リファクタリング時
- **型変更**: `find_type_usages`で全箇所特定 → `get_type_hierarchy`で継承確認 → 変更 → `search_code`で0件確認
- **関数変更**: `find_symbol_definition`で定義特定 → `search_code`で全呼び出し → 変更 → 0件確認
- **削除**: `find_type_usages`で0件確認後に削除実行

#### 検証時
- **依存関係**: `analyze_imports` - Domain→Infrastructure、Tools→他層等の違反検出
- **Mock**: `search_code("MockAssertion")`で全Mock確認
- **テスト**: `find_test_cases`で既存パターン確認
- **重複コード**: `search_code`で3箇所以上検出 → Tools/Library化判断

## Gemini MCPが利用可能な場合

- OSフレームワークの使い方や、外部APIの利用方法はGeminiに確認する
- Web検索 (Google検索) はジェミニに依頼する

## Codex MCPが利用可能な場合

- ソースコード、設計文書などの深い分析や、複雑な推論が必要な場合は、Codexに依頼する
- 特にTokenを消費するような分析は、Codexに依頼する

## その他

Claude または Claudeのsubagentsで実行する
