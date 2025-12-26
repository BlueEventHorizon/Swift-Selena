# DES-102: LSP統合設計書

**設計ID**: DES-102
**作成日**: 2025-10-24
**対象**: v0.5.1〜v0.5.5（LSP統合フェーズ）
**ステータス**: 承認待ち
**関連文書**: REQ-002, DES-101

## メタデータ

| 項目 | 値 |
|-----|-----|
| 設計ID | DES-102 |
| 対象バージョン | v0.5.1〜v0.5.5 |
| 関連要件 | REQ-002（LSP統合要件） |
| 主要コンポーネント | LSPState, LSPClient, FileLogHandler, DebugRunner |
| LSP API | initialize, initialized, didOpen, findReferences, documentSymbol, typeHierarchy |

---

## 1. LSP統合の設計方針

### 1.1 ハイブリッドアーキテクチャ

```mermaid
graph TB
    subgraph NoBuild["ビルド不可時"]
        SS[SwiftSyntax<br/>構文解析のみ]
        Result1[基本情報<br/>シンボル名・種類・行番号]
    end

    subgraph Buildable["ビルド可能時"]
        Hybrid[SwiftSyntax<br/>+<br/>LSP]
        Result2[詳細情報<br/>+ 型情報<br/>+ 正確な参照]
    end

    Project{Project<br/>Buildable?}

    Project -->|No| SS
    Project -->|Yes| Hybrid

    SS --> Result1
    Hybrid --> Result2

    Result1 --> User[User]
    Result2 --> User

    style SS fill:#c8e6c9
    style Hybrid fill:#bbdefb
```

**設計判断:**
- SwiftSyntax = ベースライン（削除しない）
- LSP = オプション強化
- ビルド非依存性の原則を維持

---

### 1.2 グレースフルデグレード

```mermaid
stateDiagram-v2
    [*] --> ToolRequest: Tool called

    ToolRequest --> CheckLSP: LSP enhanced tool?

    CheckLSP --> TryLSP: Yes
    CheckLSP --> UseSyntax: No

    TryLSP --> LSPAvailable: LSP status check

    LSPAvailable --> ExecuteLSP: Available
    LSPAvailable --> UseSyntax: Not available

    ExecuteLSP --> LSPSuccess: LSP execution
    LSPSuccess --> ReturnLSP: Success
    LSPSuccess --> UseSyntax: Failure

    UseSyntax --> ExecuteSyntax: SwiftSyntax execution
    ExecuteSyntax --> ReturnSyntax: Success

    ReturnLSP --> [*]: Result v0.5.4+
    ReturnSyntax --> [*]: Result v0.5.4+

    note right of UseSyntax
        フォールバック
        必ず結果を返す
    end note

    note right of ExecuteLSP
        try-catch
        エラーでもクラッシュしない
    end note
```

**保証:**
- どのケースでも結果を返す
- エラーで終わらない
- 代替案を提示

---

## 2. v0.5.x系 実装ロードマップ

### 2.1 バージョン別実装内容

```mermaid
gantt
    title v0.5.x LSP統合ロードマップ
    dateFormat YYYY-MM-DD
    section v0.5.1
    LSP基盤整備           :done, v51, 2025-10-21, 1d
    section v0.5.2
    find_symbol_references :done, v52, 2025-10-21, 1d
    section v0.5.3
    LSP安定化・デバッグ    :done, v53, 2025-10-21, 3d
    section v0.5.4
    ツール強化             :active, v54, 2025-10-25, 1d
    section v0.5.5
    追加機能              :v55, 2025-11-01, 7d
```

---

### 2.2 実装済み vs 計画中

```mermaid
mindmap
  rootv0.5.4+
    v0.5.1 完了
      LSPState Actor
      LSPClient基盤
      動的ツールリスト
    v0.5.2 完了
      find_symbol_references
      textDocument/references
    v0.5.3 完了
      initialized通知
      didOpen実装
      SIGPIPE対策
      FileLogHandler
      DebugRunner
    v0.5.4 計画中
      documentSymbol
      typeHierarchy
      list_symbols強化
      get_type_hierarchy強化
    v0.5.5 将来
      callHierarchy
      その他LSP API
```

---

## 3. LSPプロトコル実装

### 3.1 完全なプロトコルフロー

```mermaid
sequenceDiagram
    participant Client as LSPClient
    participant LSP as SourceKit-LSP

    Note over Client,LSP: Phase 1: Initialization

    Client->>LSP: initialize request<br/>Content-Length: XXX<br/>{"jsonrpc":"2.0","id":1,"method":"initialize",...}

    LSP->>Client: initialize response<br/>{"result":{"capabilities":{...}}}

    Note over Client: ⚠️ レスポンス読み捨て必須<br/>（v0.5.3で修正）

    Client->>LSP: initialized notification<br/>{"jsonrpc":"2.0","method":"initialized","params":{}}

    Note over LSP: ⚠️ これがないと2リクエスト後に終了<br/>（v0.5.3で発見）

    Note over Client,LSP: Phase 2: File Opening

    Client->>LSP: textDocument/didOpen<br/>{"method":"textDocument/didOpen","params":{...}}

    Note over LSP: ⚠️ これがないと"No language service"エラー<br/>（v0.5.3で発見）

    Note over Client,LSP: Phase 3: Requests

    Client->>LSP: textDocument/references<br/>{"id":3,"method":"textDocument/references",...}

    LSP->>Client: references response<br/>{"id":3,"result":[...]}

    Client->>LSP: textDocument/documentSymbol<br/>{"id":4,...}

    LSP->>Client: documentSymbol response<br/>{"id":4,"result":[...]}
```

---

### 3.2 重要な発見（v0.5.3）

```mermaid
mindmap
  rootv0.5.4+
    initialized通知
      必須
      ないと2リクエスト後に終了
      SIGPIPE発生
    didOpen通知
      ファイル毎に必須
      ないとNo language service
      openedFilesでキャッシュ
    initializeレスポンス
      読み捨て必須
      残ると誤解析
      バッファクリア
    SIGPIPE対策
      signal SIGPIPE SIG_IGN
      process.isRunning確認
      try-catch必須
    Content-Length
      正確な計算必須
      固定値200はNG
      実際のJSON長
```

---

## 4. LSPClient設計

### 4.1 クラス構造

```mermaid
classDiagram
    class LSPClient {
        -Process process
        -Pipe inputPipe
        -Pipe outputPipe
        -Pipe errorPipe
        -Int messageId
        -Set~String~ openedFiles
        +init(projectPath, logger)
        +findReferences(filePath, line, column) List~LSPLocation~
        +documentSymbol(filePath) List~LSPDocumentSymbol~
        +typeHierarchy(filePath, line, column) LSPTypeHierarchy
        +disconnect()
        -sendInitialize()
        -sendDidOpen(filePath)
        -receiveResponse() String
    }

    class LSPState {
        <<Actor>>
        -Bool isAvailable
        -LSPClient lspClient
        -String lastError
        -Int connectionAttempts
        +tryConnect(projectPath) Bool
        +isLSPAvailable() Bool
        +getClient() LSPClient
        +getStatus() Tuple
        +disconnect()
    }

    class LSPLocation {
        +String filePath
        +Int line
    }

    class LSPDocumentSymbol {
        +String name
        +Int kind
        +String detail
        +Int line
    }

    class LSPTypeHierarchy {
        +String name
        +Int kind
        +String detail
    }

    LSPState --> LSPClient : manages
    LSPClient --> LSPLocation : returns
    LSPClient --> LSPDocumentSymbol : returns
    LSPClient --> LSPTypeHierarchy : returns
```

---

### 4.2 LSP APIメソッド一覧

| メソッド | LSP Method | 入力 | 出力 | バージョン |
|---------|-----------|------|------|-----------|
| findReferences | textDocument/references | filePath, line, column | [LSPLocation] | v0.5.2 |
| documentSymbol | textDocument/documentSymbol | filePath | [LSPDocumentSymbol] | v0.5.4（計画） |
| typeHierarchy | textDocument/prepareTypeHierarchy | filePath, line, column | LSPTypeHierarchy? | v0.5.4（計画） |
| callHierarchy | textDocument/prepareCallHierarchy | filePath, line, column | CallHierarchyItem? | v0.5.5（将来） |

---

## 5. LSPプロトコル詳細

### 5.1 initialize/initialized

```mermaid
sequenceDiagram
    participant C as LSPClient
    participant L as SourceKit-LSP

    C->>C: processId取得
    C->>C: JSON作成<br/>{"jsonrpc":"2.0","id":1,...}
    C->>C: Content-Length計算<br/>実際のバイト数
    C->>L: Content-Length: 150\r\n\r\n<br/>{"jsonrpc":"2.0",...}

    L->>C: Content-Length: 500\r\n\r\n<br/>{"id":1,"result":{"capabilities":{...}}}

    C->>C: receiveResponsev0.5.4+
    Note over C: ⚠️ 読み捨て必須

    C->>C: initialized作成
    C->>L: Content-Length: 55\r\n\r\n<br/>{"jsonrpc":"2.0","method":"initialized",...}

    Note over L: Ready for requests
```

---

### 5.2 textDocument/didOpen

```mermaid
sequenceDiagram
    participant C as LSPClient
    participant FS as FileSystem
    participant L as SourceKit-LSP

    C->>FS: Read file content
    FS-->>C: File content v0.5.4+

    C->>C: JSON escape<br/>\ → \\<br/>" → \"<br/>\n → \\n

    C->>C: didOpen作成<br/>text: "escaped content"

    C->>L: Content-Length: XXX\r\n\r\n<br/>{"method":"textDocument/didOpen",...}

    C->>C: openedFiles.insertv0.5.4+

    Note over C: ⚠️ 同じファイルは1回のみ<br/>openedFilesでキャッシュ

    Note over L: File opened<br/>Language service ready
```

---

### 5.3 textDocument/references

```mermaid
sequenceDiagram
    participant T as Tool
    participant C as LSPClient
    participant L as SourceKit-LSP

    T->>C: findReferencesv0.5.4+

    C->>C: Check openedFiles
    alt File not opened
        C->>L: didOpen notification
    end

    C->>C: messageId++
    C->>C: Create request<br/>line/column v0.5.4+

    alt Process not running
        C->>T: throw LSPError.processTerminated
    end

    C->>L: Content-Length: XXX\r\n\r\n<br/>{"id":N,"method":"textDocument/references",...}

    L->>C: Response

    C->>C: Parse JSON

    alt Error response
        C->>T: return [] v0.5.4+
    else Success
        C->>T: return [LSPLocation]
    end
```

---

## 6. エラーハンドリング設計

### 6.1 エラー発生ポイントと対策

```mermaid
graph TD
    Start[LSP API Call]

    Check1{Process<br/>Running?}
    Check2{Write to<br/>Pipe OK?}
    Check3{Response<br/>Received?}
    Check4{JSON<br/>Valid?}
    Check5{Error in<br/>Response?}

    Err1[LSPError<br/>processTerminated]
    Err2[LSPError<br/>communicationFailed]
    Err3[LSPError<br/>communicationFailed]
    Err4[Return empty<br/>result]
    Err5[Return empty<br/>result]

    Success[Parse result<br/>Return data]

    Start --> Check1
    Check1 -->|No| Err1
    Check1 -->|Yes| Check2

    Check2 -->|Fail| Err2
    Check2 -->|OK| Check3

    Check3 -->|Timeout| Err3
    Check3 -->|OK| Check4

    Check4 -->|Invalid| Err4
    Check4 -->|Valid| Check5

    Check5 -->|Error| Err5
    Check5 -->|OK| Success

    Err1 --> Throw[Throw Error]
    Err2 --> Throw
    Err3 --> Throw
    Err4 --> Empty[Return empty]
    Err5 --> Empty

    style Err1 fill:#ffcdd2
    style Err2 fill:#ffcdd2
    style Err3 fill:#ffcdd2
    style Success fill:#c8e6c9
```

---

### 6.2 SIGPIPE対策（v0.5.3）

```mermaid
sequenceDiagram
    participant LSPClient
    participant Pipe as Pipe v0.5.4+
    participant LSP as sourcekit-lsp

    Note over LSPClient: signalv0.5.4+<br/>グローバル設定

    LSPClient->>LSPClient: Check process.isRunning

    alt Process Terminated
        LSPClient->>LSPClient: throw processTerminated
    end

    LSPClient->>Pipe: try writev0.5.4+

    alt Write Failed v0.5.4+
        Pipe-->>LSPClient: Error v0.5.4+
        LSPClient->>LSPClient: throw communicationFailed
    else Write Success
        Pipe->>LSP: Data transmitted
    end
```

---

## 7. デバッグ環境設計（v0.5.3）

### 7.1 FileLogHandler

```mermaid
graph LR
    Logger[Swift Logger<br/>API]
    Handler[FileLogHandler]
    File[~/.swift-selena/<br/>logs/server.log]
    Tail[tail -f<br/>監視]

    Logger -->|log message| Handler
    Handler -->|write| File
    File -->|read| Tail
    Tail -->|display| Terminal[Terminal<br/>リアルタイム表示]

    style Handler fill:#c8e6c9
    style File fill:#fff9c4
```

**ログ形式:**
```
[2025-10-24T09:30:49Z] ℹ️ [info] Starting Swift MCP Server...
[2025-10-24T09:30:51Z] ℹ️ [info] Attempting LSP connection...
[2025-10-24T09:30:51Z] ✅ [info] LSP connected successfully
```

---

### 7.2 DebugRunner設計

```mermaid
graph TB
    subgraph SameProcess["Same Process"]
        Main[SwiftMCPServer<br/>Main Thread]
        DBG[DebugRunner<br/>Detached Task]
        LSPState[LSPState<br/>Shared]
    end

    Main -->|#if DEBUG<br/>Task.detached| DBG
    Main --> LSPState
    DBG --> LSPState

    DBG -->|Wait 5 sec| TestSeq[Test Sequence]

    TestSeq --> T1[Test 1<br/>LSPState actor]
    TestSeq --> T2[Test 2<br/>ProjectMemory class]
    TestSeq --> T3[Test 3<br/>FindSymbolReferencesTool]
    TestSeq --> T4[Test 4: ...]
    TestSeq --> T5[Test 5: ...]

    T1 --> Log[File Log]
    T2 --> Log
    T3 --> Log
    T4 --> Log
    T5 --> Log

    style DBG fill:#fff9c4
    style LSPState fill:#bbdefb
    style Log fill:#c8e6c9
```

**利点:**
- 本番と同じLSPState共有
- Xcodeデバッガでブレークポイント設定可能
- 自動テストシーケンス

---

## 8. 動的ツールリスト設計

### 8.1 問題と解決策

```mermaid
graph TD
    Problem[問題:<br/>ListToolsは起動時1回のみ呼ばれる<br/>LSP接続前にツールリスト生成]

    Solution1[方式A:<br/>LSP接続を待つ]
    Solution2[方式B:<br/>後でツールリスト更新]
    Solution3[方式C:<br/>LSPツールを常に含める]

    Issue1[起動が遅くなる ❌]
    Issue2[MCPプロトコルに<br/>機能なし ❌]
    Success[実行時にチェック ✅]

    Problem --> Solution1
    Problem --> Solution2
    Problem --> Solution3

    Solution1 --> Issue1
    Solution2 --> Issue2
    Solution3 --> Success

    style Success fill:#c8e6c9
    style Issue1 fill:#ffcdd2
    style Issue2 fill:#ffcdd2
```

**採用方式（v0.5.3）:**
- find_symbol_referencesを常にツールリストに含める
- 実行時にLSP利用可能性をチェック
- 利用不可ならエラーメッセージで代替案提示

---

## 9. v0.5.4実装ガイド

### 9.1 実装するもの

```mermaid
graph TB
    V53[v0.5.3完了<br/>find_symbol_references]

    subgraph V054Impl["v0.5.4実装"]
        LC1[LSPClient.<br/>documentSymbol]
        LC2[LSPClient.<br/>typeHierarchy]
        T1[ListSymbolsTool.<br/>executeWithLSP]
        T2[GetTypeHierarchyTool.<br/>executeWithLSP]
        R1[SwiftMCPServer<br/>ルーティング分岐]
    end

    Result[list_symbols強化<br/>get_type_hierarchy強化]

    V53 --> LC1
    V53 --> LC2

    LC1 --> T1
    LC2 --> T2

    T1 --> R1
    T2 --> R1

    R1 --> Result

    style V53 fill:#c8e6c9
    style LC1 fill:#ffe0b2
    style LC2 fill:#ffe0b2
    style T1 fill:#bbdefb
    style T2 fill:#bbdefb
```

---

### 9.2 実装パターン（findReferencesと同じ）

```mermaid
flowchart TD
    Start[LSP API Method]
    DidOpen[sendDidOpen<br/>ファイルを開く]
    MsgId[messageId++]
    Req[Create Request<br/>Content-Length計算]
    Check{Process<br/>Running?}
    Write[try write to pipe]
    Recv[receiveResponse]
    Parse[Parse JSON]
    ErrCheck{Error in<br/>response?}
    Convert[Convert to struct]
    Return[Return result]

    Start --> DidOpen
    DidOpen --> MsgId
    MsgId --> Req
    Req --> Check
    Check -->|Yes| Write
    Check -->|No| Err1[throw processTerminated]
    Write -->|OK| Recv
    Write -->|Fail| Err2[throw communicationFailed]
    Recv --> Parse
    Parse --> ErrCheck
    ErrCheck -->|Yes| Empty[return empty]
    ErrCheck -->|No| Convert
    Convert --> Return

    style DidOpen fill:#fff9c4
    style Write fill:#ffe0b2
    style Convert fill:#c8e6c9
```

**全LSP APIがこのパターンを踏襲**

---

## 10. 学んだ教訓

### 10.1 v0.5.2/v0.5.3で学んだこと

```mermaid
mindmap
  rootv0.5.4+
    プロトコル仕様
      完全に読む
      他実装を参考
      ログで通信確認
    デバッグ環境
      最優先で整備
      ログなしは困難
      自動テストで再現
    段階的実装
      1バージョン1機能
      品質優先
      動作確認してから次
    後方互換性
      新フィールドはオプショナル
      マイグレーション戦略
      既存データを壊さない
```

---

## 11. v0.5.4で発見した問題（v0.5.5で修正）

### 11.1 LSP非同期通知混入問題

**発見日:** 2025-10-26（v0.5.4テスト時）

**問題の詳細:**

```mermaid
sequenceDiagram
    participant Client as LSPClient
    participant LSP as SourceKit-LSP

    Client->>LSP: textDocument/documentSymbol<br/>id=3

    par Background
        LSP-->>Client: publishDiagnostics<br/>（非同期通知）
    end

    LSP->>Client: documentSymbol response<br/>id=3

    Note over Client: receiveResponse()<br/>availableData取得

    Client->>Client: publishDiagnostics混入！<br/>JSONパース失敗

    Client->>Client: SwiftSyntax版へフォールバック
```

**実際のログ:**
```
LSP typeHierarchy response (length=196)
---START---
{"method":"textDocument/publishDiagnostics",...}  ← 非同期通知
---END---
⚠️ Failed to parse LSP typeHierarchy response as JSON
Using SwiftSyntax for list_symbols
```

**影響範囲:**
- find_symbol_references: ✅ 動作（非同期通知が少ない）
- documentSymbol: ❌ 不安定（フォールバック）
- typeHierarchy: ❌ 不安定（フォールバック）

---

### 11.2 根本原因

**現状の実装（receiveResponse）:**
```swift
let data = try? handle.availableData  // 全バッファ取得
```

**問題点:**
1. 複数メッセージが混在する
2. 非同期通知が先に読まれる
3. 実際のレスポンスを読めない

**正しい実装（v0.5.5）:**
```swift
1. Content-Lengthヘッダー読み取り
2. 指定バイト数だけ読み取り
3. 1メッセージずつ処理
4. 非同期通知（method）と応答（id）を分離
```

---

### 11.3 v0.5.5での修正計画

```mermaid
graph TD
    Start[receiveResponse改善]

    Read[Read until CRLF CRLF]
    Parse[Parse Content-Length]
    ReadBody[Read exact bytes]
    Check{Has id?}
    Response[Return as response]
    Notify[Process as notification]

    Start --> Read
    Read --> Parse
    Parse --> ReadBody
    ReadBody --> Check
    Check -->|Yes| Response
    Check -->|No| Notify

    Notify --> Read

    style Response fill:#c8e6c9
    style Notify fill:#fff9c4
```

**実装方針:**
1. ResponseBufferクラス作成
2. Content-Length正確解析
3. メッセージ種別判定（id有無）
4. 非同期通知は別処理またはスキップ

**工数:** 2-3時間

**優先度:** 🔴 最高（v0.5.5の最優先課題）

---

## 12. v0.5.4詳細設計

### 12.1 documentSymbol実装

```mermaid
sequenceDiagram
    participant Tool as ListSymbolsTool
    participant Client as LSPClient
    participant LSP as SourceKit-LSP

    Tool->>Client: documentSymbolv0.5.4+

    Client->>Client: sendDidOpenv0.5.4+
    Client->>LSP: textDocument/didOpen

    Client->>Client: messageId++
    Client->>LSP: textDocument/documentSymbol

    LSP->>Client: {"result":[<br/>  {"name":"Foo","kind":5,"detail":"class Foo"},<br/>  {"name":"bar","kind":6,"detail":"func barv0.5.4+"}...]}

    Client->>Client: Parse & Convert

    Client->>Tool: [LSPDocumentSymbol]

    Tool->>Tool: Format with type info

    Tool->>Tool: Return "Symbols v0.5.4+"
```

---

### 12.2 typeHierarchy実装

```mermaid
sequenceDiagram
    participant Tool as GetTypeHierarchyTool
    participant Syntax as SwiftSyntaxAnalyzer
    participant Client as LSPClient
    participant LSP as SourceKit-LSP

    Tool->>Syntax: getTypeHierarchyv0.5.4+
    Syntax-->>Tool: TypeInfo v0.5.4+

    Tool->>Client: typeHierarchyv0.5.4+

    Client->>Client: sendDidOpenv0.5.4+
    Client->>LSP: textDocument/didOpen

    Client->>LSP: textDocument/prepareTypeHierarchy

    LSP->>Client: {"result":[{"name":"Foo","detail":"class Foo: Bar"}]}

    Client-->>Tool: LSPTypeHierarchy

    Tool->>Tool: Combine SwiftSyntax + LSP info

    Tool->>Tool: Return "Type Hierarchy v0.5.4+:<br/>Type Detail: class Foo: Bar"
```

---

## 13. テスト戦略

### 13.1 DebugRunnerテストフロー

```mermaid
sequenceDiagram
    participant Xcode
    participant SMCP as SwiftMCPServer
    participant DR as DebugRunner
    participant Tool as FindSymbolReferencesTool
    participant LSP as LSPClient

    Xcode->>SMCP: Run v0.5.4+

    SMCP->>DR: Task.detached<br/>v0.5.4+

    Note over SMCP,DR: MCPサーバー起動<br/>LSP接続

    DR->>DR: Wait 5 seconds

    loop Test Sequence
        DR->>Tool: Call with test data
        Tool->>LSP: LSP API
        LSP-->>Tool: Result
        Tool-->>DR: Success/Failure
        DR->>DR: Log result
    end

    Note over DR: ✅ All tests passed<br/>or<br/>❌ Test N failed

    Note over Xcode: ブレークポイントで停止可能<br/>変数監視<br/>スタックトレース
```

---

### 13.2 検証結果（v0.5.3）

| テスト | 結果 |
|--------|------|
| LSPState actor | ✅ 3件検出 |
| ProjectMemory class | ✅ 34件検出 |
| FindSymbolReferencesTool | ✅ 3件検出 |
| 5回連続実行 | ✅ クラッシュなし |

---

### 13.3 検証結果（v0.5.4）

**Swift-Selena自身（Swift Package）:**

| API | 接続 | レスポンス取得 | パース | 動作 |
|-----|------|---------------|--------|------|
| find_symbol_references | ✅ | ✅ | ✅ | ✅ 完全動作 |
| documentSymbol | ✅ | ✅ (16KB) | ❌ 非同期通知混入 | △ フォールバック |
| typeHierarchy | ✅ | ✅ (196byte) | ❌ 非同期通知混入 | △ フォールバック |

**ContactBプロジェクト（Xcodeプロジェクト）:**

| ツール | LSP接続 | LSP動作 | SwiftSyntax版 | 結果 |
|--------|---------|---------|---------------|------|
| list_symbols | ✅ | ❌ | ✅ | ✅ 263ファイル完全一致 |
| analyze_imports | - | - | ✅ | ✅ 263ファイル完全一致 |
| find_files | - | - | ✅ | ✅ 263ファイル完全一致 |

**結論:**
- グレースフルデグレード完璧 ✅
- SwiftSyntax版で全機能動作 ✅
- LSP版は v0.5.5 で安定化予定

---

## 14. v0.5.4実装の最終評価

### 14.1 達成事項

**完全実装:**
- ✅ LSPClient API追加（documentSymbol, typeHierarchy）
- ✅ 階層構造対応（children再帰、90倍改善）
- ✅ 除外ディレクトリ（重大バグ修正）
- ✅ Import空ファイル対応
- ✅ ログJST表示

**部分実装:**
- △ LSP版動作（非同期通知問題、v0.5.5で完成）

### 14.2 v0.5.5への引継ぎ

**必須課題:**
1. ResponseBuffer実装（最優先）
2. documentSymbol/typeHierarchy安定化
3. 非同期通知処理

**期待効果:**
- LSP版が完全動作
- 型情報表示（detailフィールドがあれば）

---

## 15. 参照

**要件定義:**
- REQ-002: LSP統合要件

**設計書:**
- DES-101: システムアーキテクチャ
- DES-103: ツール実装設計

**履歴:**
- CONVERSATION_HISTORY.md: v0.5.2/v0.5.3開発経緯

---

**Document Version**: 2.1
**Created**: 2025-10-24
**Last Updated**: 2025-10-26
**Status**: 承認待ち
**Changes**:
- v0.5.4実装完了、検証結果追加
- LSP非同期通知問題を記載
- v0.5.5への引継ぎ事項明確化
**Supersedes**: DES-007, DES-008 DebugRunner, DES-009, Hybrid-Architecture-Plan.md（LSP部分）
