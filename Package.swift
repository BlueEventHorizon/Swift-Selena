// swift-tools-version: 6.1
// 依存パッケージ（swift-nio 2.98.0 / swift-log 1.12.0）が tools-version 6.1 を要求するため、宣言を実態に合わせる。
// 言語モードは Swift 5 のまま（Swift 6 モードでは actor isolation の警告がエラーになるため）。
import PackageDescription

let package = Package(
    name: "Swift-Selena",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // MCP Swift SDK
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.0"),
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Swift-Selena",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources"
        ),
        // SymbolVisitorV2 単体テスト（DES-104 / REQ-005 §4.4.1 受入基準対応）
        .testTarget(
            name: "SymbolVisitorV2Tests",
            dependencies: [
                "Swift-Selena",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Tests/SymbolVisitorV2Tests"
        ),
        // SearchCodeTool 単体テスト（DES-104 §11.1）
        .testTarget(
            name: "SearchCodeToolTests",
            dependencies: ["Swift-Selena"],
            path: "Tests/SearchCodeToolTests"
        ),
        // FindSymbolDefinitionTool 単体テスト（DES-104 §11.2 / REQ-005）
        .testTarget(
            name: "FindSymbolDefinitionToolTests",
            dependencies: ["Swift-Selena"],
            path: "Tests/FindSymbolDefinitionToolTests"
        ),
        // 後方互換テスト（DES-104 §11.4 / REQ-005 §4.6）
        .testTarget(
            name: "BackwardCompatibilityTests",
            dependencies: ["Swift-Selena"],
            path: "Tests/BackwardCompatibilityTests"
        ),
        // 型準拠 / Import キャッシュの無効化テスト（ファイル変更・追加・削除の追従）
        .testTarget(
            name: "TypeConformanceCacheTests",
            dependencies: ["Swift-Selena"],
            path: "Tests/TypeConformanceCacheTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
