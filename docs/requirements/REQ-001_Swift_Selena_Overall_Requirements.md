# REQ-001: Swift-Selena 全体要件定義

**要件ID**: REQ-001
**作成日**: 2025-10-24
**対象**: Swift-Selena プロジェクト全体
**ステータス**: 承認待ち
**関連文書**: Swift-Selena Design.md, PLAN.md

---

## 1. 要求背景

### 1.1 解決すべき課題

#### 課題1: 実装中コードの解析困難

**状況:**
- Swift開発中、コードを書いている最中はビルドエラーが存在する
- SourceKit-LSP、Xcodeは「ビルド可能なコード」が前提
- 実装中の中途半端なコードでは解析機能が使えない

**影響:**
- AIアシスタント（Claude）がコードを理解できない
- リファクタリング中に構造を把握できない
- 「ビルドを通してから解析」では開発効率が悪い

**具体例:**
```swift
// 実装中のコード（ビルドエラー）
class UserManager {
    func createUser() {
        // TODO: 実装中
        let user = User()  // ← User型が未定義、ビルドエラー
    }

    func deleteUser() {  // ← このメソッドの存在を知りたい
        // ...
    }
}
```

**現状のツール:**
- SourceKit-LSP: ビルドエラーで動作しない❌
- Xcode: ビルドエラーで補完が効かない❌
- grep/ripgrep: 構造を理解できない❌

**求められる解決策:**
✅ ビルドエラーがあっても、クラス構造・メソッド一覧を把握できる

---

#### 課題2: プライバシーとセキュリティ

**状況:**
- クローズドソースプロジェクト、機密情報を含むコード
- 外部APIにコードを送信したくない
- ローカル完結が必須

**現状のツール:**
- GitHub Copilot: クラウド送信❌
- ChatGPT Code Interpreter: クラウド送信❌
- Claude API: クラウド送信（ただしMCPでローカル実行可能）

**求められる解決策:**
✅ 完全ローカル実行、外部通信なし

---

#### 課題3: パフォーマンスと軽量性

**状況:**
- 大規模プロジェクト（1000+ファイル）での解析
- 即座に結果が欲しい（数秒以内）
- IDEの重さは避けたい

**現状のツール:**
- Xcode: 重い、インデックス構築に時間がかかる❌
- SourceKit-LSP: ビルド必要、初回遅い❌

**求められる解決策:**
✅ ファイルシステムベースの高速検索、キャッシュによる高速化

---

### 1.2 ターゲットユーザー

#### プライマリユーザー

**1. AIアシスタント利用のSwift開発者**
- Claude Code、Claude Desktopユーザー
- AIにコード理解させたい
- リファクタリング、バグ修正で使用

**2. 大規模Swiftプロジェクトの開発者**
- 既存コードベースの理解
- アーキテクチャ把握
- 依存関係の可視化

**3. SwiftUI開発者**
- Property Wrapper（@State, @Binding）の追跡
- Protocol準拠の確認
- ビュー階層の理解

#### セカンダリユーザー

**4. Swiftライブラリ開発者**
- API設計のレビュー
- テストカバレッジの確認
- ドキュメント生成支援

---

### 1.3 競合比較

| 機能 | Swift-Selena | Serena | SourceKit-LSP | Xcode |
|------|-------------|--------|---------------|-------|
| **ビルド不要** | ✅ | ✅ | ❌ | ❌ |
| **Swift特化** | ✅ | ❌ | ✅ | ✅ |
| **プライバシー** | ✅ | ✅ | ✅ | ✅ |
| **MCP統合** | ✅ | ✅ | ❌ | ❌ |
| **型情報** | △（LSP時）| ❌ | ✅ | ✅ |
| **SwiftUI解析** | ✅ | ❌ | △ | ✅ |
| **軽量・高速** | ✅ | ✅ | △ | ❌ |

**Swift-Selenaの独自価値:**
- ビルド不要 + Swift特化 + SwiftUI解析 + MCP統合

---

## 2. 現状の課題

### 2.1 既存ツールの限界

#### Serena（汎用MCPサーバー）

**強み:**
- 多言語対応（Python, Java, C++, Swift等）
- ビルド不要
- MCP統合

**限界:**
- Swift特有の機能（Property Wrapper）は解析できない
- SwiftUIの@State、@Bindingを理解できない
- Protocolの継承関係が浅い

**例:**
```swift
@State private var counter = 0

// Serenaでは:
// → "counter" という変数があることは分かる
// → @State であることは分からない
// → SwiftUIの状態管理であることは理解できない
```

---

#### SourceKit-LSP

**強み:**
- 型情報が完全
- 参照検索が正確
- Apple公式

**限界:**
- ビルド可能が前提
- 実装中のコードでは動作しない
- 単独では使いにくい（エディタ統合前提）

**例:**
```swift
class UserManager {
    func createUser() {
        let user = User()  // ← User未定義、ビルドエラー
    }
}

// SourceKit-LSP:
// → ビルドエラーで解析不能 ❌
// → UserManager クラスの存在すら認識できない
```

---

#### Xcode

**強み:**
- 統合環境
- リアルタイム解析
- SwiftUI完全対応

**限界:**
- IDE依存（CLI/MCP統合困難）
- 重い
- AIアシスタントとの連携に制約

---

### 2.2 開発者が困っていること

#### シーン1: リファクタリング中

```swift
// 既存コード（動作中）
class OldUserManager {
    func createUser(name: String) { ... }
    func deleteUser(id: Int) { ... }
}

// リファクタリング中（ビルドエラー）
class UserManager {
    // 新しい設計で書き直し中...
    func create() {  // ← まだ実装途中
        // TODO
    }
}
```

**困っていること:**
- OldUserManagerのメソッド一覧を見たい
- どこで使われているか確認したい
- でも、ビルドエラーで既存ツールが使えない

**Swift-Selenaでの解決:**
```
list_symbols("OldUserManager.swift")
→ ✅ createUser, deleteUser メソッドが見える

find_type_usages("OldUserManager")
→ ✅ 使用箇所が分かる
```

---

#### シーン2: SwiftUIコード理解

```swift
struct ContentView: View {
    @State private var counter = 0
    @Binding var isPresented: Bool
    @StateObject var viewModel: ViewModel

    var body: some View { ... }
}
```

**困っていること:**
- どの変数が状態管理か分からない
- @State, @Binding, @StateObjectの違いを把握したい
- AIに説明させたいが、構造が分からない

**Swift-Selenaでの解決:**
```
list_property_wrappers("ContentView.swift")
→ ✅ counter: @State
→ ✅ isPresented: @Binding
→ ✅ viewModel: @StateObject
```

---

#### シーン3: 大規模プロジェクトの理解

```
MyApp/（1000+ files）
├─ Domain/
│  ├─ Entity/
│  ├─ Repository/
│  └─ UseCase/
├─ Infrastructure/
└─ Presentation/
```

**困っていること:**
- どのファイルに何があるか分からない
- 型の継承関係が複雑
- Import依存関係を把握したい

**Swift-Selenaでの解決:**
```
find_files("*Repository.swift")
→ ✅ 全Repositoryファイルを発見

get_type_hierarchy("BaseRepository")
→ ✅ 継承関係を可視化

analyze_imports()
→ ✅ モジュール依存を把握
```

---

## 3. 要件定義

### 3.1 機能要件

#### FR-001: ビルド非依存の解析

**要件:**
- ビルドエラーがあっても、構文が正しければ解析できること
- SwiftSyntaxベースのAST解析

**受入基準:**
- 構文エラーがないコードは100%解析可能
- ビルドエラー（型不一致等）があっても解析可能

---

#### FR-002: Swift特化解析

**要件:**
- Property Wrapper検出
- Protocol準拠解析
- Extension解析
- テストケース検出
- 型使用箇所検出

**受入基準:**
- @State, @Binding, @ObservedObjectを100%検出
- Protocol準拠を正確に抽出
- XCTestクラスを100%検出

---

#### FR-003: ローカル完結性

**要件:**
- 外部APIへの通信なし
- 全処理をローカルマシンで実行
- ネットワーク接続不要

**受入基準:**
- インターネット切断状態でも動作
- ファイアウォールログに通信記録なし

---

#### FR-004: MCP統合

**要件:**
- MCPプロトコル準拠
- Claude Code/Claude Desktopで使用可能
- stdio通信

**受入基準:**
- MCP Swift SDK 0.10.2準拠
- Claude Code/Claude Desktopで動作確認

---

#### FR-005: 永続化とキャッシュ

**要件:**
- 解析結果を永続化
- セッション間でデータ共有
- ファイル変更検出と自動無効化

**受入基準:**
- 再起動後も同じプロジェクトデータを使用
- ファイル更新時に古いキャッシュを破棄

---

#### FR-006: LSP統合（v0.5.1+）

**要件:**
- ビルド可能時はLSPで高度な機能提供
- LSP利用不可時はSwiftSyntaxで動作（グレースフルデグレード）
- 動的ツールリスト生成

**受入基準:**
- ビルド可能時: find_symbol_referencesが利用可能
- ビルド不可時: 17個のSwiftSyntaxツールが動作
- LSP接続失敗でもクラッシュしない

---

### 3.2 非機能要件

#### NFR-001: パフォーマンス

**要件:**
- 1000ファイルプロジェクトで10秒以内
- ファイル検索は1秒以内
- メモリ使用量100MB以下

**現状:**
- 340ファイルで初回3-5秒（キャッシュなし）
- 2回目以降0.5秒（キャッシュあり）

---

#### NFR-002: 信頼性

**要件:**
- クラッシュ率0%
- エラーは適切なメッセージで返す
- プロセスが死んでもログが残る

**v0.5.3での達成:**
- ✅ FileLogHandler実装
- ✅ エラーハンドリング網羅
- ✅ SIGPIPE対策

---

#### NFR-003: 保守性

**要件:**
- コードの可読性
- ドキュメント完備
- テストデバッグ環境

**v0.5.3での達成:**
- ✅ DebugRunner実装
- ✅ 詳細ログ出力
- ✅ 設計書完備

---

## 4. ユースケース

### UC-001: AIアシスタントによるコード理解

**アクター:** Claude Code使用中の開発者

**前提条件:**
- SwiftプロジェクトをClaude Codeで開いている
- Swift-Selena MCPサーバーが設定済み

**メインフロー:**
```
1. 開発者: 「このファイルの構造を説明して」
2. Claude: initialize_project("/path/to/project")
3. Claude: list_symbols("UserManager.swift")
4. Claude: 「UserManagerには以下のメソッドがあります...」
```

**期待される結果:**
- ビルドエラーがあっても構造を説明できる
- Property Wrapper、Protocol準拠も含めて理解
- 正確な行番号で参照可能

**成功基準:**
- 開発者が満足する説明が得られる
- 5秒以内に応答

---

### UC-002: リファクタリング影響範囲の確認

**アクター:** SwiftUIアプリ開発者

**シナリオ:**
```swift
// ViewModelの名前を変更したい
class UserViewModel { ... }

// どこで使われているか確認したい
```

**フロー:**
```
1. 開発者: 「UserViewModelの使用箇所を教えて」
2. Claude: find_type_usages("UserViewModel")
3. Claude: 「15箇所で使用されています」
4. 開発者: リファクタリング実施
```

**LSP版（v0.5.2+、ビルド可能時）:**
```
2. Claude: find_symbol_references("UserViewModel.swift", line, column)
3. Claude: 「18箇所で使用されています（より正確）」
```

**期待される結果:**
- 全ての使用箇所を漏れなく発見
- ファイルパスと行番号を取得

---

### UC-003: SwiftUI Property Wrapperの追跡

**アクター:** SwiftUI初心者

**シナリオ:**
```swift
struct ProfileView: View {
    @State private var name = ""
    @Binding var isPresented: Bool
    @StateObject var viewModel: ProfileViewModel
    @ObservedObject var settings: Settings
    @EnvironmentObject var appState: AppState
```

**問題:**
- どれが状態管理で、どれが外部から注入されるのか分からない

**フロー:**
```
1. 開発者: 「このViewの状態管理を説明して」
2. Claude: list_property_wrappers("ProfileView.swift")
3. Claude: 「@Stateはローカル状態、@Bindingは親からの参照...」
```

**期待される結果:**
- Property Wrapperを完全に列挙
- 型情報も含めて理解

---

### UC-004: Protocol準拠の確認

**アクター:** アーキテクト、コードレビュアー

**シナリオ:**
```swift
class UserRepository: RepositoryProtocol, Loggable {
    // ...
}
```

**フロー:**
```
1. レビュアー: 「このクラスは何のProtocolを実装してる？」
2. Claude: list_protocol_conformances("UserRepository.swift")
3. Claude: 「RepositoryProtocol と Loggable を実装」
```

**期待される結果:**
- Protocol準拠を完全に抽出
- 継承元のスーパークラスも表示

---

### UC-005: テストカバレッジの確認

**アクター:** QAエンジニア

**フロー:**
```
1. QA: 「どのテストケースがある？」
2. Claude: find_test_cases()
3. Claude: 「UserManagerTests に3つのテストメソッド...」
```

**期待される結果:**
- XCTestクラスを全て発見
- テストメソッドを列挙

---

### UC-006: Import依存関係の把握

**アクター:** アーキテクト

**フロー:**
```
1. アーキテクト: 「このプロジェクトのモジュール依存を見せて」
2. Claude: analyze_imports()
3. Claude: 「Foundationが最も使われています（120ファイル）...」
```

**期待される結果:**
- 全Importを集計
- モジュール使用頻度を表示
- キャッシュで高速化

---

## 5. 成功基準

### 5.1 定量的指標

| 指標 | 目標値 | v0.5.3実績 |
|------|--------|-----------|
| ツール数 | 18個 | 18個 ✅ |
| ビルド不要ツール | 17個 | 17個 ✅ |
| LSPツール | 1-3個 | 1個 ✅ |
| Property Wrapper検出率 | 100% | 100% ✅ |
| Protocol準拠検出率 | 100% | 100% ✅ |
| クラッシュ率 | 0% | 0% ✅ |
| パフォーマンス（340ファイル） | <5秒 | 3-5秒 ✅ |

---

### 5.2 定性的評価

#### 評価1: 開発者体験

**目標:**
- ビルドエラーを気にせず解析できる
- AIアシスタントが正確にコードを理解
- ストレスなく使える

**評価方法:**
- 実際のプロジェクトで使用
- フィードバック収集

---

#### 評価2: SwiftUI開発支援

**目標:**
- Property Wrapperを完全に理解
- 状態管理フローを把握
- SwiftUI特有の構造を解析

**評価方法:**
- SwiftUIプロジェクトでの使用実績
- Property Wrapper検出の正確性

---

#### 評価3: 大規模プロジェクト対応

**目標:**
- 1000+ファイルでも快適に動作
- メモリ枯渇しない
- キャッシュが有効

**評価方法:**
- 大規模プロジェクトでのベンチマーク
- メモリ使用量測定

---

## 6. 制約条件

### 6.1 技術的制約

**必須:**
- macOS 13.0+
- Swift 5.9+
- SwiftSyntax 602.0.0

**オプション:**
- SourceKit-LSP（LSP機能使用時）

---

### 6.2 設計制約

**原則:**
1. **ビルド非依存性の維持**
   - LSP統合後もSwiftSyntax版を維持
   - グレースフルデグレード必須

2. **ローカル完結性**
   - 外部サーバー接続なし
   - プライバシー保護

3. **段階的強化**
   - SwiftSyntax = ベースライン
   - LSP = オプション強化

4. **運用の現実**
   - メンテナンスフリー
   - 自動更新対応

---

## 7. スコープ外（実装しないもの）

### 7.1 コード変更機能

**理由:**
- 読み取り専用ツール
- コード生成・修正はClaude本体の役割

### 7.2 ビルド機能

**理由:**
- ビルドはswift build、Xcodeの役割
- Swift-Selenaは解析専門

### 7.3 リアルタイム監視

**理由:**
- ファイル変更の自動検出はしない
- 必要時に都度解析

### 7.4 GUI提供

**理由:**
- MCPサーバーとして動作
- UIはClaude Code/Claude Desktopが提供

---

## 8. リリース計画

### 8.1 v0.5.x系（LSP統合）

**目標:**
- SwiftSyntax + LSP のハイブリッド
- ビルド可能時の高度な機能

**マイルストーン:**
- ✅ v0.5.0: リファクタリング、22ツール
- ✅ v0.5.1: LSP基盤整備
- ✅ v0.5.2: find_symbol_references
- ✅ v0.5.3: LSP安定化、デバッグ機能
- ⏳ v0.5.4: list_symbols/get_type_hierarchy強化
- ⏳ v0.5.5: get_call_hierarchy

---

### 8.2 v0.6.x系（Code Header DB）

**目標:**
- 意図ベース検索
- 「ユーザー登録の機能はどこ？」で検索

**v0.5.xとの関係:**
- v0.5.x: 構造ベース解析（「UserManagerクラス」を検索）
- v0.6.x: 意図ベース検索（「ユーザー管理」を検索）

---

### 8.3 v1.0.0（安定版）

**目標:**
- 全機能完成
- 本番環境対応
- テストカバレッジ80%+

---

## 9. ステークホルダー

### 9.1 プライマリステークホルダー

**開発者（ユーザー）:**
- Swiftコード解析ツールが必要
- AIアシスタント活用したい
- プライバシー重視

**期待:**
- ビルド不要で使える
- 高速・軽量
- SwiftUI対応

---

### 9.2 セカンダリステークホルダー

**Anthropic（Claude提供者）:**
- MCPエコシステム充実
- Swift開発者のClaude利用促進

**オープンソースコミュニティ:**
- Swift解析ツールの選択肢増加
- MCP実装の参考事例

---

## 10. リスクと対策

### 10.1 技術リスク

#### リスク1: LSP統合の複雑さ

**発生確率**: 中
**影響度**: 大

**v0.5.3での教訓:**
- initialized通知、didOpenの欠落でクラッシュ
- LSPプロトコル仕様の完全理解が必須

**対策:**
- 段階的実装（v0.5.1〜v0.5.5）
- DebugRunnerによる自動テスト
- グレースフルデグレード必須

---

#### リスク2: SwiftSyntaxバージョン依存

**発生確率**: 低
**影響度**: 中

**対策:**
- 特定バージョンに固定（602.0.0 exact）
- 破壊的変更時は別途対応

---

### 10.2 運用リスク

#### リスク3: ユーザーの理解不足

**発生確率**: 中
**影響度**: 中

**対策:**
- ドキュメント充実
- README.mdに具体例
- エラーメッセージに代替案提示

---

## 11. 将来の拡張性

### 11.1 v0.6.0以降

**Code Header DB:**
- 意図ベース検索
- NaturalLanguageによる形態素解析

**Prompts機能:**
- MCP Prompts Capability活用
- 分析モード提供

**コメント検索:**
- TODO/FIXME検出
- ドキュメントコメント解析

---

### 11.2 v1.0.0

**統計・分析:**
- コード品質メトリクス
- 依存関係可視化
- プロジェクト健全性レポート

---

## 12. 承認事項

### 12.1 要件の優先順位

**最高優先:**
1. ビルド非依存性
2. ローカル完結性
3. Swift特化解析

**高優先:**
4. MCP統合
5. SwiftUI対応
6. LSP統合

**中優先:**
7. Code Header DB
8. 統計機能

---

### 12.2 実装スコープ

**v0.5.x系:**
- SwiftSyntax基本機能（完了）
- LSP統合（進行中）

**v0.6.x系以降:**
- 高度な検索機能
- 統計・分析

---

## 13. 参照文書

**設計文書:**
- Swift-Selena Design.md
- Hybrid-Architecture-Plan.md
- PLAN.md

**実装文書:**
- DES-007: LSP基盤（v0.5.1）
- DES-008: DebugRunner
- DES-009: list_symbols/get_type_hierarchy強化（v0.5.4）

**履歴:**
- HISTORY.md
- CONVERSATION_HISTORY.md

---

**Document Version**: 1.0
**Created**: 2025-10-24
**Last Updated**: 2025-10-24
**Status**: 承認待ち
