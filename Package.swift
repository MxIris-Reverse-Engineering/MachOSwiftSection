// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MachOSwiftSection",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "MachOSwiftSection",
            targets: ["MachOSwiftSection"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/p-x9/MachOKit.git", from: "0.30.0"),
        .package(url: "https://github.com/p-x9/MachOObjCSection", branch: "main"),
        .package(url: "https://github.com/oozoofrog/SwiftDemangle", branch: "main"),
        .package(url: "https://github.com/mattgallagher/CwlDemangle", branch: "master"),
    ],
    targets: [
        .target(
            name: "MachOSwiftSection",
            dependencies: [
                .product(name: "MachOKit", package: "MachOKit"),
                .product(name: "MachOObjCSection", package: "MachOObjCSection"),
                .product(name: "SwiftDemangle", package: "SwiftDemangle"),
                .product(name: "CwlDemangle", package: "CwlDemangle"),
            ]
        ),
        .testTarget(
            name: "MachOSwiftSectionTests",
            dependencies: [
                "MachOSwiftSection",
                .product(name: "MachOKit", package: "MachOKit"),
                .product(name: "MachOObjCSection", package: "MachOObjCSection"),
                .product(name: "SwiftDemangle", package: "SwiftDemangle"),
                .product(name: "CwlDemangle", package: "CwlDemangle"),
            ]
        ),
    ]
)
