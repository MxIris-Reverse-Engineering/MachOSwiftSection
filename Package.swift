// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MachOSwiftSection",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(
            name: "MachOSwiftSection",
            targets: ["MachOSwiftSection"]),
    ],
    dependencies: [
        .package(url: "https://github.com/p-x9/MachOKit.git", from: "0.30.0"),
    ],
    targets: [
        .target(
            name: "MachOSwiftSection",
            dependencies: [
                .product(name: "MachOKit", package: "MachOKit"),
            ]
        ),
        .testTarget(
            name: "MachOSwiftSectionTests",
            dependencies: ["MachOSwiftSection"]
        ),
    ]
)
