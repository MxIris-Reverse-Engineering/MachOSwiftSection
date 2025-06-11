// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let useSPMPrebuildVersion = false

extension Package.Dependency {
    static let MachOKit: Package.Dependency = {
        if useSPMPrebuildVersion {
            return .MachOKitSPM
        } else {
            return .MachOKitMain
        }
    }()

    static let MachOKitOrigin = Package.Dependency.package(
        url: "https://github.com/p-x9/MachOKit.git",
        from: "0.34.0"
    )

    static let MachOKitMain = Package.Dependency.package(
        url: "https://github.com/MxIris-Reverse-Engineering/MachOKit",
        branch: "main"
    )

    static let MachOKitSPM = Package.Dependency.package(
        url: "https://github.com/p-x9/MachOKit-SPM",
        from: "0.34.0"
    )
}

extension Target.Dependency {
    static let MachOKit: Target.Dependency = {
        if useSPMPrebuildVersion {
            return .MachOKitSPM
        } else {
            return .MachOKitMain
        }
    }()

    static let MachOKitMain = Target.Dependency.product(
        name: "MachOKit",
        package: "MachOKit"
    )
    static let MachOKitSPM = Target.Dependency.product(
        name: "MachOKit",
        package: "MachOKit-SPM"
    )
    static let SwiftSyntax = Target.Dependency.product(
        name: "SwiftSyntax",
        package: "swift-syntax"
    )
    static let SwiftSyntaxMacros = Target.Dependency.product(
        name: "SwiftSyntaxMacros",
        package: "swift-syntax"
    )
    static let SwiftCompilerPlugin = Target.Dependency.product(
        name: "SwiftCompilerPlugin",
        package: "swift-syntax"
    )
    static let SwiftSyntaxMacrosTestSupport = Target.Dependency.product(
        name: "SwiftSyntaxMacrosTestSupport",
        package: "swift-syntax"
    )
    static let SwiftSyntaxBuilder = Target.Dependency.product(
        name: "SwiftSyntaxBuilder",
        package: "swift-syntax"
    )
}

let package = Package(
    name: "MachOSwiftSection",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(
            name: "MachOSwiftSection",
            targets: ["MachOSwiftSection"]
        ),
        .library(
            name: "SwiftDump",
            targets: ["SwiftDump"]
        ),
        .executable(
            name: "swift-section",
            targets: ["swift-section"]
        ),
    ],
    dependencies: [
        .MachOKit,
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "601.0.1"),
        .package(url: "https://github.com/MxIris-Library-Forks/AssociatedObject", branch: "main"),
        .package(url: "https://github.com/p-x9/swift-fileio.git", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.1"),
    ],
    targets: [
        .target(
            name: "Semantic"
        ),
        .target(
            name: "Demangle",
            dependencies: [
                "Semantic",
            ]
        ),
        .target(
            name: "MachOExtensions",
            dependencies: [
                .MachOKit,
            ]
        ),

        .target(
            name: "MachOReading",
            dependencies: [
                .MachOKit,
                "MachOMacro",
                "MachOExtensions",
                .product(name: "FileIO", package: "swift-fileio"),
                .product(name: "AssociatedObject", package: "AssociatedObject"),
            ]
        ),
        .target(
            name: "MachOPointer",
            dependencies: [
                .MachOKit,
                "MachOReading",
                "MachOMacro",
            ]
        ),
        .target(
            name: "MachOFoundation",
            dependencies: [
                .MachOKit,
                "MachOReading",
                "MachOExtensions",
                "MachOMacro",
                "MachOPointer",
            ]
        ),

        .target(
            name: "MachOSwiftSection",
            dependencies: [
                "Demangle",
                "MachOFoundation",
                "MachOMacro",
                .MachOKit,
            ]
        ),

        .target(
            name: "MachOTestingSupport",
            dependencies: [
                .MachOKit,
                "MachOExtensions",
            ]
        ),

        .target(
            name: "SwiftDump",
            dependencies: [
                .MachOKit,
                "MachOSwiftSection",
                "Semantic",
            ]
        ),
        .executableTarget(
            name: "swift-section",
            dependencies: [
                "SwiftDump",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "MachOMacro",
            dependencies: [
                "MachOMacroPlugin",
            ]
        ),

        .macro(
            name: "MachOMacroPlugin",
            dependencies: [
                .SwiftSyntax,
                .SwiftSyntaxMacros,
                .SwiftCompilerPlugin,
                .SwiftSyntaxBuilder,
            ]
        ),

        .testTarget(
            name: "DemangleTests",
            dependencies: [
                "Demangle",
            ]
        ),

        .testTarget(
            name: "MachOSwiftSectionTests",
            dependencies: [
                "MachOSwiftSection",
                "SwiftDump",
                "MachOTestingSupport",
            ]
        ),

        .testTarget(
            name: "SwiftDumpTests",
            dependencies: [
                "SwiftDump",
                "MachOTestingSupport",
            ]
        ),
    ]
)
