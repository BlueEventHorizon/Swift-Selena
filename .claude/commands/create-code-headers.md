# 全SwiftファイルにAI検索可能なコードヘッダーコメントを生成・追加する

## 使用方法

```
/create-code-headers                              # 全ファイル対象
/create-code-headers --update                     # 全ファイル上書き
/create-code-headers --changed                    # git変更ファイルのみ
/create-code-headers Sources/Tools/*              # Toolsディレクトリ配下のみ
/create-code-headers Sources/LSP/*.swift          # 特定パターン
/create-code-headers ProjectMemory.swift FileSearcher.swift  # 個別ファイル指定
```

**モード**:
- **デフォルト**: `[Code Header Format]`マーカーがあるファイルはスキップ
- **--update**: すべてのファイルで生成・上書き
- **--changed**: git変更ファイルのみ対象

**ファイル指定**:
- ワイルドカード対応（`*`, `**`）
- 拡張子省略時は自動的に`.swift`を追加
- 相対パス/絶対パス両対応
- 複数ファイル/パターン指定可能（スペース区切り）

## 実行フロー

### Step 1: ファイルスキャン

**スキャン方法の判定**:

#### ファイル/パターン指定あり

**実行**:
```
引数からファイルパターンを取得
→ ワイルドカード展開（Glob）
→ 拡張子省略時は自動的に.swift追加
→ 除外パターンでフィルタリング
```

**例**:
```
Sources/Tools/* → Glob("Sources/Tools/*.swift")
Sources/LSP/LSPClient → Sources/LSP/LSPClient.swift
Sources/**/*.swift → そのままGlob実行
```

#### --changed の場合

**実行**:
```bash
git status --porcelain
```

**処理**:
1. 変更ファイルリストから`.swift`ファイルのみ抽出
2. 除外パターンでフィルタリング
3. ファイル数を表示

#### デフォルト・--update（引数なし）

**対象ディレクトリ**:
```
Sources/**/*.swift
Tests/**/*.swift
```

**実行**:
- Glob()で対象ファイルをスキャン
- 除外パターンでフィルタリング
- ファイル数を表示

**除外パターン（共通）**:
- ファイル名に `Test` または `Tests` を含む
- ファイル名が `Mock` で始まる
- `Preview Content/` ディレクトリ配下

**出力例**:
```
対象ファイルをスキャン中...
✅ 対象: 166ファイル
✅ 対象: 5ファイル（--changedモード）
✅ 対象: 2ファイル（DI/*）
```

### Step 2: 並行処理でヘッダー生成

**複数Agentを並行起動**:
- `code-header-generator` Agentを並行起動
- 各Agentが1ファイルずつ処理
- 同時実行数: 5-10 Agent（システム負荷に応じて調整）

**重要**: 複数のTask toolを**1つのメッセージで同時に呼び出す**

**Agent起動**:
- **デフォルトモード**: `Task(prompt="対象ファイル: AppVersion.swift")`（モード指定なし）
- **更新モード**: `Task(prompt="対象ファイル: AppVersion.swift, モード: update")`

**進捗表示**:
```
コードヘッダー生成中...
[=========>        ] 50/166 (30%)
- 生成: 30件
- スキップ: 20件
```

### Step 3: 完了報告

**出力例**:
```
✅ コードヘッダー生成完了

処理結果:
- 対象ファイル: 166件
- 新規生成: 50件
- 更新: 0件（--updateモード時のみ）
- スキップ: 116件（既存ヘッダーあり）
- エラー: 0件

次のステップ:
- Swift-Selena MCPでDB構築（将来実装）
- search_code()で検索可能
```

## 注意事項

- 処理時間: 166ファイルで約10-20分（並行処理による）
- エラー発生時は該当ファイルをスキップして続行
- Copyrightヘッダーは変更しない
