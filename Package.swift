// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftMCPServer",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // MCP Swift SDK
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.10.2"),
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftMCPServer",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources"
        )
    ]
)
