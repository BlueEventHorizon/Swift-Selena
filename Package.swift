// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftMCPServer",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // MCP Swift SDK
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.2")
    ],
    targets: [
        .executableTarget(
            name: "SwiftMCPServer",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources"
        )
    ]
)
