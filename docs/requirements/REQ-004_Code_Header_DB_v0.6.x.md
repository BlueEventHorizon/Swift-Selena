# REQ-004: Code Header DB（v0.6.x）要件定義書

**要件ID**: REQ-004
**作成日**: 2024-12-28
**対象**: v0.6.0 - Code Header DB構築システム
**ステータス**: 承認待ち
**関連文書**: DES-006, DES-005, code_header_format.md

---

## 1. 要求背景

### 1.1 解決すべき課題

DES-005で各Swiftファイルに生成されたCode Headerフォーマットが存在するが、現状では以下の問題がある：

**現状の問題**:
- Code Headerを検索するには`search_code`で全ファイルを正規表現検索する必要がある
- 検索速度が遅い（200ファイルで5分）
- 検索精度が低い（完全一致のみ、同義語を理解できない）
- ノイズが多い（実装コードもヒットする）

**解決方法**:
- Code HeaderをパースしてDB化（ProjectMemory内）
- NLEmbedding（Apple Intelligence）を使ったセマンティック検索
- 高速検索（0.1秒以内）
- 高精度検索（80-90%）

**具体例**:
```
Before（search_code使用）:
User: 「電話番号をフォーマットする機能はどこ？」
Claude: search_code("電話番号.*フォーマット")
        → 50箇所ヒット（実装コード含む）
        → 5分かかる
        → 「どれが目的のファイルか分からない」

After（Code Header DB使用）:
User: 「電話番号を綺麗に表示する機能はどこ？」
Claude: search_code_headers("電話番号を綺麗に表示")
        → 2箇所ヒット（Code Headerのみ）
        → 0.07秒で完了
        → 「PhoneNumber+Format.swift」を発見
        → AIが「綺麗に表示」≈「フォーマット」を理解
```

---

## 2. 現状の問題

### 2.1 既存ツールの限界

**search_code（既存）**:
- ❌ 正規表現のみ（完全一致）
- ❌ 全ファイル走査（遅い）
- ❌ 実装コードもヒット（ノイズ多い）
- ❌ 同義語を理解できない

**find_files（既存）**:
- ❌ ファイル名検索のみ
- ❌ Code Header内容を検索できない

**find_symbol_definition（既存）**:
- ❌ シンボル名検索のみ
- ❌ 目的・機能では検索できない

### 2.2 開発者のペインポイント

1. **「何をするファイルか」が分からない**
   - 大規模プロジェクト（200+ファイル）で目的のファイルを見つけるのに10-30分
   - ファイル名から機能が推測できない（`Util.swift`等）

2. **検索が遅い**
   - `search_code`で全ファイル走査に5分
   - 複数回検索すると時間がかかりすぎる

3. **検索精度が低い**
   - 「バリデーション」で検索しても「検証」は見つからない
   - 「綺麗に表示」で検索しても「フォーマット」は見つからない

---

## 3. 要件定義

### 3.1 機能要件

#### FR-004-001: Code Header DB構築

**要件:**
- 全SwiftファイルのCode Headerをパースし、内部DBに格納する
- 各Code Headerの埋め込みベクトル（NLEmbedding）を生成してキャッシュ
- ProjectMemoryに永続化

**入力:**
- プロジェクトパス

**出力:**
- `codeHeaderCache: [String: CodeHeaderInfo]`（ファイルパス → Code Header情報 + 埋め込みベクトル）

**条件:**
- `[Code Header Format]`マーカーが存在するファイルのみ対象
- マーカーがないファイルは無視（エラーにしない）
- 埋め込みベクトルはキャッシュ（再生成しない）

**受け入れ基準:**
- 200ファイルのDB構築が15秒以内に完了
- 埋め込みベクトルがキャッシュに保存される
- 再起動後もキャッシュが保持される

---

#### FR-004-002: セマンティック検索（search_code_headers）

**要件:**
- 自然言語クエリでCode Headerを検索
- NLEmbeddingによるセマンティックマッチング
- スコア順（類似度順）に結果を返す

**入力:**
- `query`: 検索クエリ（自然言語、例: "電話番号を綺麗に表示"）
- `section`: 検索対象セクション（all/purpose/feature/type、オプション）
- `layer`: レイヤーフィルタ（Tools/Library/Domain等、オプション）
- `threshold`: 類似度閾値（0.0-1.0、デフォルト: 0.6）

**出力:**
- 検索結果リスト（ファイルパス、スコア、マッチしたセクション）
- スコア降順にソート

**条件:**
- DB未構築時は自動構築（初回のみ10-15秒）
- クエリの埋め込みベクトルを生成
- キャッシュ済み埋め込みとコサイン類似度を計算
- 閾値以上のファイルのみ返す

**受け入れ基準:**
- 検索が0.1秒以内に完了（DB構築後）
- 同義語を理解する（「綺麗に表示」≈「フォーマット」）
- 検索精度80%以上（実データでテスト）

**検索精度の定義:**
```
精度 = 期待する結果が含まれていた検索数 / 全検索数

例: 10回検索して8回期待する結果が上位3件に含まれた
→ 精度80%
```

---

#### FR-004-003: 統計情報取得（get_code_header_stats）

**要件:**
- Code Header DB統計情報を表示
- 適用率、層別統計、未適用ファイルリスト

**入力:**
- なし

**出力:**
```
📊 Code Header DB Statistics

総ファイル数: 200
Code Header適用済み: 150 (75%)
未適用: 50 (25%)

層別統計:
  Tools: 67/67 (100%)
  Library: 48/48 (100%)
  Domain: 20/30 (67%)
  App: 15/55 (27%)

DB情報:
  埋め込み次元数: 768
  最終DB構築: 2024-12-28 10:30
  キャッシュサイズ: 2.5MB

未適用ファイル（上位10件）:
  - App/Views/ContentView.swift
  - App/ViewModels/MainViewModel.swift
  ...
```

**条件:**
- DB未構築時は自動構築
- 層別統計は自動判定（ファイルパスから）

**受け入れ基準:**
- 統計情報が正確
- 実行が1秒以内

---

#### FR-004-004: DB自動更新

**要件:**
- ファイル変更検知で自動的にキャッシュ無効化
- 変更されたファイルのみ再パース・再埋め込み

**条件:**
- `lastModified`（最終更新日時）でファイル変更を検知
- 変更ファイルのみ更新（全体再構築しない）

**受け入れ基準:**
- ファイル変更後、次回検索で自動更新
- 変更されていないファイルは再処理しない

---

### 3.2 非機能要件

#### NFR-004-001: パフォーマンス

**要件:**
- DB構築時間: 200ファイル < 15秒
- 検索時間: < 0.1秒（DB構築後）
- メモリ使用量: < 50MB（DB + 埋め込みキャッシュ）

**測定方法:**
```swift
// ベンチマーク
let start = Date()
let results = try await searchCodeHeaders(query: "テスト")
let elapsed = Date().timeIntervalSince(start)
assert(elapsed < 0.1)
```

---

#### NFR-004-002: 検索精度

**要件:**
- 検索精度: 80%以上

**測定方法:**
- 実際のプロジェクト（ContactB等）で10-20回検索
- 期待する結果が上位3件に含まれる割合を測定

**テストクエリ例:**
```
1. "電話番号のフォーマット" → 期待: PhoneNumber+Format.swift
2. "バリデーション機能" → 期待: ValidationRule.swift
3. "データの永続化" → 期待: DataStore.swift
...
```

---

#### NFR-004-003: スケーラビリティ

**要件:**
- 1000ファイルプロジェクトでも動作
- DB構築時間: < 1分
- 検索時間: < 0.5秒

---

#### NFR-004-004: 互換性

**要件:**
- macOS 15+ (Sequoia)
- Apple Silicon (M1+)
- NLEmbedding日本語対応必須

**確認方法:**
```swift
guard let embedding = NLEmbedding.wordEmbedding(for: .japanese) else {
    throw CodeHeaderError.embeddingUnavailable
}
```

---

#### NFR-004-005: データ永続性

**要件:**
- 埋め込みベクトルをProjectMemoryに永続化
- 再起動後も保持
- ファイル変更検知で自動更新

---

### 3.3 制約事項

#### C-004-001: NLEmbedding依存

**制約:**
- NLEmbedding（日本語）が利用可能な環境でのみ動作
- macOS 15未満ではエラー

**対応:**
- エラーメッセージで要件を明示
- 将来的にフォールバック（形態素解析）を検討（v0.6.1+）

---

#### C-004-002: Code Header必須

**制約:**
- Code Headerが適用されていないファイルは検索対象外

**対応:**
- get_code_header_statsで未適用ファイルを表示
- DES-005のCode Header生成を推奨

---

#### C-004-003: 日本語のみサポート

**制約:**
- 英語プロジェクトには対応しない（v0.6.0時点）

**対応:**
- 将来的に英語対応を検討（v0.7.0+）

---

### 3.4 ツール仕様

#### Tool 1: search_code_headers

**名前**: `search_code_headers`

**説明**: Search Code Header Format with natural language (semantic search using Apple Intelligence)

**パラメータ:**
```json
{
  "type": "object",
  "properties": {
    "query": {
      "type": "string",
      "description": "Search query in natural language (e.g., '電話番号のフォーマット')"
    },
    "section": {
      "type": "string",
      "enum": ["all", "purpose", "feature", "type"],
      "description": "Search target section (optional, default: all)"
    },
    "layer": {
      "type": "string",
      "enum": ["all", "Tools", "Library", "Domain", "App", "Infrastructure", "DI"],
      "description": "Filter by layer (optional, default: all)"
    },
    "threshold": {
      "type": "number",
      "description": "Similarity threshold (0.0-1.0, default: 0.6)"
    }
  },
  "required": ["query"]
}
```

**出力例:**
```
🔍 Search Results for "電話番号のフォーマット"

Found 2 files (0.07s):

1. Tools/Contact/PhoneNumber+Format.swift (Score: 0.92)
   目的:
   - 電話番号の国際フォーマット対応
   - 7カ国の番号体系に対応

   主要機能:
   - 国別フォーマット適用
   - ハイフン・括弧の自動挿入

2. Library/String+PhoneFormat.swift (Score: 0.78)
   目的:
   - 文字列の電話番号フォーマット

   主要機能:
   - 正規表現ベースのフォーマット
```

---

#### Tool 2: get_code_header_stats

**名前**: `get_code_header_stats`

**説明**: Get Code Header database statistics and coverage

**パラメータ:**
```json
{
  "type": "object",
  "properties": {}
}
```

**出力例:**
上記「FR-004-003」参照

---

## 4. 受け入れ基準

### 4.1 機能面

- [ ] search_code_headersで自然言語検索ができる
- [ ] 同義語を理解する（「綺麗に表示」≈「フォーマット」）
- [ ] セクション別検索ができる（purpose/feature/type）
- [ ] レイヤーフィルタが機能する
- [ ] get_code_header_statsで統計情報が表示される
- [ ] 未適用ファイルリストが表示される

### 4.2 性能面

- [ ] DB構築: 200ファイル < 15秒
- [ ] 検索: < 0.1秒
- [ ] 検索精度: 80%以上

### 4.3 品質面

- [ ] エラーハンドリングが適切
- [ ] ログ出力が充実
- [ ] ProjectMemoryに正しく保存される
- [ ] 再起動後もキャッシュが保持される

---

## 5. テスト計画

### 5.1 単体テスト

- CodeHeaderParserのテスト
- 埋め込みベクトル生成のテスト
- コサイン類似度計算のテスト

### 5.2 統合テスト

- 実プロジェクト（ContactB）でのDB構築テスト
- 10-20クエリでの検索精度テスト
- パフォーマンステスト

### 5.3 受け入れテスト

- 実際の開発フローでの使用
- ユーザー（開発者）からのフィードバック

---

## 6. リリース基準

### v0.6.0リリース条件

- [ ] 全機能要件が実装済み
- [ ] 全非機能要件を満たす
- [ ] 受け入れ基準を全てクリア
- [ ] ドキュメント整備（README.md、CHANGELOG.md）
- [ ] DEBUGビルドでテスト完了

---

## 7. 将来の拡張（Out of Scope）

以下はv0.6.0では実装しない（v0.6.1以降で検討）：

- 類義語辞書（検索精度向上）
- 英語対応
- フォールバック検索（形態素解析）
- rebuild_code_header_db ツール（手動再構築）
- 検索履歴・学習機能

---

## 8. リスク評価

### R-004-001: NLEmbeddingのパフォーマンス

**リスク**: 埋め込み生成が予想より遅い可能性

**影響**: DB構築時間が15秒を超える

**対策**:
- 実装前にベンチマークテスト実施
- 並行処理で高速化
- プログレス表示でUX改善

### R-004-002: 検索精度が80%未満

**リスク**: セマンティック検索でも精度が不十分

**影響**: ユーザー満足度低下

**対策**:
- 閾値調整
- v0.6.1で類義語辞書追加
- フィードバックベースの改善

### R-004-003: Code Header適用率が低い

**リスク**: プロジェクトのCode Header適用率が50%以下

**影響**: 検索対象ファイルが少ない

**対策**:
- get_code_header_statsで可視化
- Code Header生成を推奨
- 未適用ファイルへの警告

---

## 9. 関連文書

- **DES-006**: Code Header DB構築システム設計書（NLEmbedding版に改訂予定）
- **DES-005**: Code Header生成システム設計書
- **code_header_format.md**: Code Headerフォーマット仕様
- **PLAN.md**: v0.6.0開発計画

---

**Document Version**: 1.0
**最終更新**: 2024-12-28
