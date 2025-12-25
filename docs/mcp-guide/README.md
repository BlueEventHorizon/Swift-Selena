# MCP開発ガイド

このディレクトリには、**汎用的なMCP（Model Context Protocol）サーバー開発のガイド**を収録しています。

Swift-Selena固有の内容ではなく、他のMCPサーバープロジェクトでも活用できる内容です。

---

## ドキュメント一覧

| ファイル | 内容 | 対象者 |
|---------|------|--------|
| [MCP-Implementation-Guide.md](MCP-Implementation-Guide.md) | MCP実装の詳細ガイド | 初めてMCPサーバーを作る人 |
| [MCP-SDK-Deep-Dive.md](MCP-SDK-Deep-Dive.md) | Swift MCP SDKの詳細解説 | SDKの内部動作を理解したい人 |
| [MCP-Best-Practices.md](MCP-Best-Practices.md) | 開発で得たベストプラクティス | 実装で躓いた人 |

---

## クイックスタート

### 1. 最小限のMCPサーバー

```swift
import MCP
import Foundation

@main
struct MinimalMCPServer {
    static func main() async throws {
        let server = Server(
            name: "minimal-server",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )

        // ツールリスト
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                Tool(
                    name: "hello",
                    description: "Say hello",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "name": .object([
                                "type": .string("string"),
                                "description": .string("Name to greet")
                            ])
                        ]),
                        "required": .array([.string("name")])
                    ])
                )
            ])
        }

        // ツール実行
        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            case "hello":
                guard let args = params.arguments,
                      let name = args["name"] else {
                    throw MCPError.invalidParams("Missing name")
                }
                return CallTool.Result(content: [
                    .text("Hello, \(name)!")
                ])
            default:
                throw MCPError.invalidParams("Unknown tool")
            }
        }

        // サーバー起動
        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()  // 重要: EOFまで待機
    }
}
```

### 2. Package.swift

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MinimalMCPServer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.10.2")
    ],
    targets: [
        .executableTarget(
            name: "MinimalMCPServer",
            dependencies: [.product(name: "MCP", package: "swift-sdk")]
        )
    ]
)
```

### 3. Claude Codeへの登録

```bash
claude mcp add minimal-server -- /path/to/.build/debug/MinimalMCPServer
```

---

## よくある質問

### Q: なぜ `waitUntilCompleted()` が必要？

`server.start()` は非ブロッキングで即座にreturnします。
`waitUntilCompleted()` がないとプロセスが即終了します。

### Q: ログはどこに出力すべき？

stdoutはMCP通信用なので、stderrまたはファイルへ出力してください。

### Q: 開発版と本番版を分離するには？

別名で登録: `claude mcp add your-server-debug -- /path/to/debug/YourServer`

---

## 参考リンク

- [MCP 公式サイト](https://modelcontextprotocol.io/)
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
- [Anthropic MCP ドキュメント](https://docs.anthropic.com/en/docs/build-with-claude/model-context-protocol)
