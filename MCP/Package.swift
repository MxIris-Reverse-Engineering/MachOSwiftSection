// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-section-mcp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "swift-section-mcp", targets: ["swift-section-mcp"]),
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    ],
    targets: [
        .executableTarget(
            name: "swift-section-mcp",
            dependencies: [
                .product(name: "SwiftDump", package: "MachOSwiftSection"),
                .product(name: "SwiftInterface", package: "MachOSwiftSection"),
                .product(name: "MachOSwiftSection", package: "MachOSwiftSection"),
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
    ]
)
