// swift-tools-version: 5.9
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
        )
    ]
)
