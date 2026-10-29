# DES-103: ツール実装設計書

**設計ID**: DES-103
**作成日**: 2025-10-24
**対象**: 全18ツール（v0.5.3時点）
**ステータス**: 承認待ち
**関連文書**: REQ-003, DES-101, DES-102

## メタデータ

| 項目 | 値 |
|-----|-----|
| 設計ID | DES-103 |
| 対象バージョン | v0.5.3 |
| 関連要件 | REQ-003（コア機能要件） |
| ツール数 | 18個 |
| カテゴリ | Project(1), FileSystem(2), Symbols(3), SwiftUI(3), Analysis(4), LSP(1), Notes(2), Prompts(2) |

---

## 1. ツール実装パターン

### 1.1 基本実装フロー

```mermaid
flowchart TD
    Start[MCP CallTool Request]
    Parse[Parse Parameters<br/>ToolHelpers.getString等]
    Validate{Validation}
    Memory{ProjectMemory<br/>Required?}
    Execute[Execute Logic<br/>Analyzer-Searcher]
    Cache["Cache Result<br/>if-applicable"]
    Format[Format Result<br/>Text-output]
    Return[Return CallTool.Result]

    Error1[MCPError<br/>invalidParams]
    Error2[MCPError<br/>invalidRequest]

    Start --> Parse
    Parse --> Validate
    Validate -->|Invalid| Error1
    Validate -->|Valid| Memory
    Memory -->|Required & Missing| Error2
    Memory -->|OK| Execute
    Execute --> Cache
    Cache --> Format
    Format --> Return

    style Execute fill:#c8e6c9
    style Format fill:#bbdefb
    style Error1 fill:#ffcdd2
    style Error2 fill:#ffcdd2
```

---

### 1.2 LSP強化パターン（v0.5.4+）

```mermaid
flowchart TD
    Start[Tool Called]
    Check{LSP<br/>Enhanced?}
    LSPAvail{LSP<br/>Available?}
    TryLSP[Execute<br/>LSP版]
    LSPSuccess{Success?}
    Syntax[Execute<br/>SwiftSyntax版]
    Return[Return Result]

    Start --> Check
    Check -->|No| Syntax
    Check -->|Yes| LSPAvail

    LSPAvail -->|Yes| TryLSP
    LSPAvail -->|No| Syntax

    TryLSP --> LSPSuccess
    LSPSuccess -->|Yes| Return
    LSPSuccess -->|No| Syntax

    Syntax --> Return

    style TryLSP fill:#ffe0b2
    style Syntax fill:#c8e6c9
    style Return fill:#bbdefb
```

**保証:** LSP失敗でも必ずSwiftSyntax版で動作

---

## 2. ツールカテゴリ構成

### 2.1 18ツールの分類

```mermaid
mindmap
  root((18 Tools))
    Project Management
      initialize_project
    File System
      find_files
      search_code
    Symbols
      list_symbols
      find_symbol_definition
      read_symbol 未実装
    SwiftUI
      list_property_wrappers
      list_protocol_conformances
      list_extensions
    Analysis
      analyze_imports
      get_type_hierarchy
      find_test_cases
      find_type_usages 削除済み
    LSP
      find_symbol_references 削除済み
    Notes
      add_note
      search_notes
    Prompts
      set_analysis_mode
      think_about_analysis
```

> ⚠️ 上記は v0.5.x 時点の分類。`find_symbol_references`（LSP）は 2025-10-27 `commit f0a547f` で、`find_type_usages`（Analysis）は 2025-12-06 `commit 580b1f7` で削除済み（§4.4 / REQ-005 §6.3）。`read_symbol`（Symbols）は計画のみで未実装。現行の公開ツールは `Sources/Constants.swift` の `ToolNames` / `MetaToolRegistry` を正とする。

---

### 2.2 ツール間の関係

```mermaid
graph TB
    Init[initialize_project<br/>必須・最初に実行]

    subgraph DiscoveryTools["Discovery Tools"]
        FF[find_files<br/>ファイル発見]
        SC[search_code<br/>コード検索]
    end

    subgraph AnalysisTools["Analysis Tools"]
        LS[list_symbols<br/>シンボル一覧]
        FSD[find_symbol_definition<br/>定義検索]
        AI[analyze_imports<br/>依存関係]
        GTH[get_type_hierarchy<br/>継承階層]
    end

    subgraph SwiftUITools["SwiftUI Tools"]
        LPW[list_property_wrappers]
        LPC[list_protocol_conformances]
        LE[list_extensions]
    end

    subgraph HistoricalLSPTools["Historical LSP Tools"]
        FSR[find_symbol_references<br/>削除済み]
    end

    Init --> FF
    Init --> SC
    Init --> LS
    Init --> FSD
    Init --> AI
    Init --> GTH
    Init --> LPW
    Init --> LPC
    Init --> LE
    Init --> FSR

    FF -.-> LS
    LS -.-> FSD
    LS -.-> FSR

    style Init fill:#e1bee7
    style FSR fill:#ffe0b2
```

---

## 3. SwiftSyntax Visitor実装

### 3.1 Visitorパターン

```mermaid
graph LR
    Source[Swift Source<br/>File]
    Parser[Parser.parse<br/>構文解析]
    AST[Syntax Tree<br/>AST]
    Visitor[Visitor.walk<br/>AST走査]
    Result[Extracted Info<br/>結果]

    Source --> Parser
    Parser --> AST
    AST --> Visitor
    Visitor --> Result

    style Parser fill:#c8e6c9
    style Visitor fill:#bbdefb
```

---

### 3.2 実装済みVisitor

```mermaid
mindmap
  root((Visitors))
    SymbolVisitor
      Class, Struct検出
      Enum, Protocol検出
      Function検出
    PropertyWrapperVisitor
      @State検出
      @Binding検出
      @StateObject等
    ExtensionVisitor
      Extension検出
      Protocol準拠
      メンバー抽出
    TypeConformanceVisitor
      スーパークラス
      Protocol準拠
      継承関係
    ImportVisitor
      Import文抽出
      モジュール名
    TypeUsageVisitor
      変数宣言
      関数パラメータ
      戻り値型
    XCTestVisitor
      XCTestCase継承
      testメソッド
```

---

### 3.3 Visitor実装フロー

```mermaid
sequenceDiagram
    participant Tool
    participant Analyzer as SwiftSyntaxAnalyzer
    participant Parser
    participant Visitor
    participant Converter as SourceLocationConverter

    Tool->>Analyzer: listSymbols(filePath)
    Analyzer->>Analyzer: Read file
    Analyzer->>Parser: Parser.parse(source)
    Parser-->>Analyzer: SourceFileSyntax
    Analyzer->>Converter: Create converter
    Analyzer->>Visitor: SymbolVisitor(...)
    Analyzer->>Visitor: walk(sourceFile)

    loop Each Node
        Visitor->>Visitor: visit(node)
        Visitor->>Converter: Get line number
        Visitor->>Visitor: Store info
    end

    Visitor-->>Analyzer: visitor.symbols
    Analyzer-->>Tool: [SymbolInfo]
```

---

## 4. ツール実装詳細（主要ツールのみ）

### 4.1 initialize_project

```mermaid
flowchart TD
    Start[initialize_project]
    Validate[Validate project path]
    Create[Create ProjectMemory]
    LSPTask[Task.detached<br/>LSP接続試行]
    Immediate[Immediate response<br/>非ブロッキング]

    Start --> Validate
    Validate --> Create
    Create --> LSPTask
    Create --> Immediate

    LSPTask -.->|Background| LSPConnect[tryConnect]
    LSPConnect -.-> LSPReady[LSP Ready]

    Immediate --> Return[Return success]

    style LSPTask fill:#fff9c4
    style Immediate fill:#c8e6c9
```

**特徴:** LSP接続を待たない（ユーザー体験優先）

---

### 4.2 list_symbols（SwiftSyntax版）

```mermaid
flowchart LR
    Input[Swift File]
    Parse[Parser.parse]
    Visitor[SymbolVisitor<br/>Class/Struct/Func検出]
    Format["Format result<br/>Class Foo line 10<br/>Function bar line 20"]
    Output[Result]

    Input --> Parse
    Parse --> Visitor
    Visitor --> Format
    Format --> Output

    style Visitor fill:#c8e6c9
```

---

### 4.3 list_symbols（LSP版、v0.5.4+）

```mermaid
flowchart TD
    Input[list_symbols request]
    CheckLSP{LSP<br/>Available?}
    LSPPath[LSPClient.<br/>documentSymbol]
    SyntaxPath[SwiftSyntax<br/>Analyzer]
    FormatLSP["Format with type info<br/>Class Foo - class Foo<br/>Method bar - func bar"]
    FormatSyntax["Format basic<br/>Class Foo<br/>Function bar"]
    Output[Result]

    Input --> CheckLSP
    CheckLSP -->|Yes| LSPPath
    CheckLSP -->|No| SyntaxPath

    LSPPath -->|Success| FormatLSP
    LSPPath -->|Fail| SyntaxPath

    SyntaxPath --> FormatSyntax

    FormatLSP --> Output
    FormatSyntax --> Output

    style LSPPath fill:#ffe0b2
    style SyntaxPath fill:#c8e6c9
```

---

### 4.4 find_symbol_references（LSP専用）

> ⚠️ **削除済み**（2025-10-27 `commit f0a547f`「find_symbol_referencesを削除」、REQ-005 §6.3）。以下は削除前の実装設計を歴史的記録として保持する。LSP 系参照検索ツールの再導入可否は別途独立 Feature として検討する。

```mermaid
flowchart TD
    Input[find_symbol_references<br/>filePath, line, column]
    CheckLSP{LSP<br/>Client?}
    Error[MCPError<br/>LSP not available<br/>+ 代替案提示]
    DidOpen[sendDidOpen<br/>filePath]
    Request[findReferences<br/>LSP API]
    Success{Result?}
    Format["Format result<br/>Found N references<br/>file-line<br/>..."]
    Empty[No references found]
    Output[Result]

    Input --> CheckLSP
    CheckLSP -->|No| Error
    CheckLSP -->|Yes| DidOpen

    DidOpen --> Request
    Request --> Success

    Success -->|Found| Format
    Success -->|Empty| Empty

    Format --> Output
    Empty --> Output

    style Request fill:#ffe0b2
    style Format fill:#c8e6c9
    style Error fill:#ffcdd2
```

---

### 4.5 list_property_wrappers（SwiftUI）

```mermaid
flowchart LR
    Input[SwiftUI File]
    Parse[Parser.parse]
    Visitor["PropertyWrapperVisitor<br/>State-Binding検出"]
    Extract["Extract info<br/>wrapper-type<br/>property-name<br/>type-name"]
    Format["Format result<br/>State counter-Int<br/>Binding isPresented-Bool"]
    Output[Result]

    Input --> Parse
    Parse --> Visitor
    Visitor --> Extract
    Extract --> Format
    Format --> Output

    style Visitor fill:#c8e6c9
```

---

### 4.6 analyze_imports（キャッシュ活用）

```mermaid
flowchart TD
    Start[analyze_imports]

    subgraph ForEachSwiftFile["For each Swift file"]
        Check{File in<br/>Cache?}
        Modified{File<br/>Modified?}
        UseCache[Use cached imports]
        Analyze[Parse & extract imports]
        Update[Update cache]
    end

    Aggregate[Aggregate all imports]
    Count[Count by module]
    Sort[Sort by frequency]
    Format[Format result]
    Return[Return]

    Start --> Check
    Check -->|No| Analyze
    Check -->|Yes| Modified

    Modified -->|No| UseCache
    Modified -->|Yes| Analyze

    Analyze --> Update
    Update --> Aggregate
    UseCache --> Aggregate

    Aggregate --> Count
    Count --> Sort
    Sort --> Format
    Format --> Return

    style UseCache fill:#c8e6c9
    style Analyze fill:#ffe0b2
```

---

### 4.7 get_type_hierarchy（SwiftSyntax版）

```mermaid
flowchart TD
    Start[get_type_hierarchy<br/>typeName]

    subgraph CollectTypeInfo["Collect Type Info"]
        Scan[Scan all files<br/>キャッシュ利用]
        Find[Find type definition]
        FindSuper[Find superclass]
        FindSub[Find subclasses]
        FindProto[Find protocols]
    end

    Format[Format hierarchy tree]
    Return[Return]

    Start --> Scan
    Scan --> Find
    Find --> FindSuper
    Find --> FindSub
    Find --> FindProto

    FindSuper --> Format
    FindSub --> Format
    FindProto --> Format

    Format --> Return

    style Scan fill:#fff9c4
    style Format fill:#c8e6c9
```

---

## 5. ツールヘルパー設計

### 5.1 ToolHelpers

```mermaid
classDiagram
    class ToolHelpers {
        <<Enum>>
        +requireProjectMemory(ProjectMemory?) ProjectMemory$
        +getString(args, key, errorMessage) String$
        +getInt(args, key, defaultValue) Int$
        +getBool(args, key, defaultValue) Bool$
    }

    class Tool {
        +execute(params, projectMemory, logger)
    }

    Tool --> ToolHelpers : uses
```

**目的:** パラメータ処理の共通化、コード重複削減

---

### 5.2 定数定義構造

```mermaid
graph TB
    subgraph ConstantsSwift["Constants.swift"]
        AC[AppConstants<br/>name, version]
        TN[ToolNames<br/>全ツール名]
        PK[ParameterKeys<br/>パラメータキー]
        EM[ErrorMessages<br/>エラーメッセージ]
    end

    subgraph Usage["Usage"]
        Tool[Tool Definitions]
        Param[Parameter Processing]
        Error[Error Handling]
    end

    TN --> Tool
    PK --> Param
    EM --> Error

    style AC fill:#e1bee7
    style TN fill:#bbdefb
    style PK fill:#c8e6c9
    style EM fill:#ffccbc
```

---

## 6. 新ツール追加フロー

### 6.1 実装手順

```mermaid
flowchart TD
    Start[新ツール追加]
    File["Create Tool file<br/>Tools-Category-NewTool.swift"]
    Protocol[Implement MCPTool]
    Definition[toolDefinition実装]
    Execute[execute実装]
    Constants[Add to ToolNames]
    Register1[Add to ListTools]
    Register2[Add to CallTool]
    Test[Test with DebugRunner]
    Done[Complete]

    Start --> File
    File --> Protocol
    Protocol --> Definition
    Protocol --> Execute
    Execute --> Constants
    Constants --> Register1
    Constants --> Register2
    Register2 --> Test
    Test --> Done

    style File fill:#fff9c4
    style Execute fill:#c8e6c9
    style Test fill:#ffe0b2
```

**所要時間:** 15-30分/ツール

---

### 6.2 Visitor追加フロー

```mermaid
flowchart TD
    Start[新Visitor追加]
    File["Create Visitor file<br/>Visitors-NewVisitor.swift"]
    Inherit[Inherit SyntaxVisitor]
    Override[Override visit methods]
    LineNum[Implement getLineNumber]
    Integrate[Integrate to Analyzer]
    Test[Test]
    Done[Complete]

    Start --> File
    File --> Inherit
    Inherit --> Override
    Override --> LineNum
    LineNum --> Integrate
    Integrate --> Test
    Test --> Done

    style Override fill:#c8e6c9
    style Integrate fill:#bbdefb
```

**所要時間:** 30-60分/Visitor

---

## 7. キャッシュ設計

### 7.1 キャッシュ構造

```mermaid
erDiagram
    ProjectMemory ||--o{ FileInfo : "fileIndex"
    ProjectMemory ||--o{ SymbolInfo : "symbolCache"
    ProjectMemory ||--o{ ImportInfo : "importCache"
    ProjectMemory ||--o{ TypeConformanceInfo : "typeConformanceCache"

    FileInfo {
        String path PK
        Date lastModified
        Int symbolCount
    }

    SymbolInfo {
        String name
        String kind
        String filePath
        Int line
    }

    ImportInfo {
        String filePath PK
        String module
        String kind
        Int line
    }

    TypeConformanceInfo {
        String filePath PK
        String typeName
        String typeKind
        String superclass
        Array protocols
    }
```

---

### 7.2 キャッシュ無効化フロー

```mermaid
flowchart TD
    Request[Tool Request<br/>for file]
    GetCache[Get from cache]
    Check{Cache<br/>exists?}
    CheckMod{File<br/>modified?}
    Valid[Use cache]
    Invalid[Invalidate]
    Analyze[Re-analyze]
    Update[Update cache]
    Return[Return result]

    Request --> GetCache
    GetCache --> Check
    Check -->|No| Analyze
    Check -->|Yes| CheckMod

    CheckMod -->|No| Valid
    CheckMod -->|Yes| Invalid

    Invalid --> Analyze
    Analyze --> Update
    Update --> Return
    Valid --> Return

    style Valid fill:#c8e6c9
    style Analyze fill:#ffe0b2
```

**判定:** `FileInfo.lastModified < FileManager.modificationDate`

---

## 8. エラーハンドリング

### 8.1 エラーレベル設計

```mermaid
graph TB
    Error[Error Occurred]

    Level{Error<br/>Level}

    Params[Invalid Parameters<br/>ユーザー入力ミス]
    Request[Invalid Request<br/>前提条件未達]
    Internal[Internal Error<br/>サーバー側問題]

    MsgParams[明確なパラメータ説明]
    MsgRequest[前提条件と解決方法]
    MsgInternal[詳細エラー + 代替案]

    Error --> Level

    Level --> Params
    Level --> Request
    Level --> Internal

    Params --> MsgParams
    Request --> MsgRequest
    Internal --> MsgInternal

    MsgParams --> User[User]
    MsgRequest --> User
    MsgInternal --> User

    style MsgParams fill:#fff9c4
    style MsgRequest fill:#ffccbc
    style MsgInternal fill:#ffcdd2
```

---

### 8.2 エラーメッセージ設計原則

```mermaid
mindmap
  root((エラーメッセージ))
    What
      何が起きたか
      明確に説明
    Why
      なぜ失敗したか
      原因を示す
    How
      どうすれば解決するか
      代替案提示
    Tone
      親切に
      建設的に
```

**例:**
```
❌ LSP not available.

This tool requires a buildable project with SourceKit-LSP.

💡 Alternatives:
- Use 'search_code' for text-based reference search
- Use 'find_symbol_definition' to locate the definition and its scope
```

---

## 9. パフォーマンス最適化

### 9.1 最適化戦略

```mermaid
graph TB
    subgraph FileLevel["ファイルレベル"]
        Exclude[除外ディレクトリ<br/>.build, .git等]
        Cache1[ファイルキャッシュ<br/>lastModified比較]
    end

    subgraph AnalysisLevel["解析レベル"]
        Cache2[シンボルキャッシュ<br/>find_symbol_definition高速化]
        Cache3[Importキャッシュ<br/>analyze_imports高速化]
    end

    subgraph ExecutionLevel["実行レベル"]
        Async[非同期処理<br/>LSP接続バックグラウンド]
        Lazy[遅延評価<br/>必要な時だけ解析]
    end

    Performance[高速化]

    Exclude --> Performance
    Cache1 --> Performance
    Cache2 --> Performance
    Cache3 --> Performance
    Async --> Performance
    Lazy --> Performance

    style Performance fill:#c8e6c9
```

---

### 9.2 パフォーマンス目標

| 指標 | 目標 | v0.5.3実績 |
|------|------|-----------|
| 340ファイル（初回） | <5秒 | 3-5秒 ✅ |
| 340ファイル（キャッシュ） | <1秒 | 0.5秒 ✅ |
| 1000ファイル | <10秒 | 未測定 |
| メモリ使用量 | <100MB | 未測定 |

---

## 10. テスト設計

### 10.1 DebugRunnerテスト

```mermaid
graph LR
    DR[DebugRunner<br/>#if DEBUG]
    Seq[Test Sequence]
    T1[Test 1]
    T2[Test 2]
    T3[Test 3]
    T4[Test 4]
    T5[Test 5]
    Log[Log Results]
    Verify[Verify<br/>All passed?]

    DR --> Seq
    Seq --> T1
    Seq --> T2
    Seq --> T3
    Seq --> T4
    Seq --> T5

    T1 --> Log
    T2 --> Log
    T3 --> Log
    T4 --> Log
    T5 --> Log

    Log --> Verify

    style DR fill:#fff9c4
    style Verify fill:#c8e6c9
```

---

### 10.2 Xcodeデバッグフロー

```mermaid
flowchart TD
    Start[Xcodeで実行]
    Wait[5秒待機]
    Auto[DebugRunner<br/>自動実行]
    Break[Breakpoint<br/>停止]
    Inspect[変数監視<br/>スタックトレース]
    Step[ステップ実行]
    Fix[問題特定・修正]

    Start --> Wait
    Wait --> Auto
    Auto --> Break
    Break --> Inspect
    Inspect --> Step
    Step --> Fix

    style Break fill:#fff9c4
    style Inspect fill:#c8e6c9
```

---

## 11. 将来の拡張

### 11.1 v0.5.4での追加

```mermaid
graph LR
    V53[v0.5.3<br/>find_symbol_references<br/>削除済み]
    V54[v0.5.4<br/>+ documentSymbol<br/>+ typeHierarchy]
    Enhanced[2ツール強化<br/>list_symbols<br/>get_type_hierarchy]

    V53 --> V54
    V54 --> Enhanced

    style V53 fill:#c8e6c9
    style V54 fill:#ffe0b2
    style Enhanced fill:#bbdefb
```

---

### 11.2 v0.5.5での追加

```mermaid
graph LR
    V54[v0.5.4<br/>ツール強化]
    V55[v0.5.5<br/>+ callHierarchy<br/>+ その他API]
    More[さらなる機能]

    V54 --> V55
    V55 --> More

    style V55 fill:#fff9c4
    style More fill:#ffccbc
```

---

## 12. 参照

**要件定義:**
- REQ-003: コア機能要件

**設計書:**
- DES-101: システムアーキテクチャ
- DES-102: LSP統合設計

---

**Document Version**: 2.0
**Created**: 2025-10-24
**Last Updated**: 2025-10-24
**Status**: 承認待ち
**Changes**: mermaid図中心に再構成、詳細コード削減
**Supersedes**: （既存ツール実装の暗黙知を明文化）
