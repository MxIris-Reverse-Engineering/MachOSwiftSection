// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let useSPMPrebuildVersion = false

extension Package.Dependency {
    static let MachOKit: Package.Dependency = {
        if useSPMPrebuildVersion {
            return .MachOKitSPM
        } else {
            return .MachOKitMain
        }
    }()

    static let MachOKitMain = Package.Dependency.package(url: "https://github.com/p-x9/MachOKit.git", from: "0.31.0")
    static let MachOKitSPM = Package.Dependency.package(url: "https://github.com/p-x9/MachOKit-SPM", branch: "main")
}

extension Target.Dependency {
    static let MachOKit: Target.Dependency = {
        if useSPMPrebuildVersion {
            return .MachOKitSPM
        } else {
            return .MachOKitMain
        }
    }()

    static let MachOKitMain = Target.Dependency.product(name: "MachOKit", package: "MachOKit")
    static let MachOKitSPM = Target.Dependency.product(name: "MachOKit", package: "MachOKit-SPM")
}

let package = Package(
    name: "MachOSwiftSection",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "MachOSwiftSection",
            targets: ["MachOSwiftSection"]
        ),
    ],
    dependencies: [
        .MachOKit,
    ],
    targets: [
        .target(
            name: "MachOSwiftSection",
            dependencies: [
                "Demangling",
                .MachOKit,
            ]
        ),
        .target(
            name: "Demangling"
        ),
        .testTarget(
            name: "MachOSwiftSectionTests",
            dependencies: [
                "MachOSwiftSection",
                .MachOKit,
            ]
        ),
        .testTarget(
            name: "DemanglingTests",
            dependencies: [
                "Demangling",
            ]
        ),
    ]
)
