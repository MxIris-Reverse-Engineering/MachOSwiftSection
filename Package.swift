// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let useSPMPrebuildVersion = true

extension Package.Dependency {
    static let MachOKit: Package.Dependency = {
        if useSPMPrebuildVersion {
            return .MachOKitSPM
        } else {
            return .MachOKitMain
        }
    }()

    static let MachOKitMain = Package.Dependency.package(
        url: "https://github.com/p-x9/MachOKit.git",
        from: "0.34.0"
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
    ],
    dependencies: [
        .MachOKit,
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "601.0.1"),
        .package(url: "https://github.com/MxIris-Library-Forks/AssociatedObject", branch: "main"),
        .package(url: "https://github.com/p-x9/swift-fileio.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "Demangle"
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
                "MachOPointer"
            ]
        ),
        
        .target(
            name: "MachOSwiftSection",
            dependencies: [
                "Demangle",
                "MachOFoundation",
                "MachOMacro",
                .MachOKit,
                .product(name: "AssociatedObject", package: "AssociatedObject"),
            ]
        ),

        .target(
            name: "SwiftDump",
            dependencies: [
                "MachOSwiftSection",
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
            name: "MachOSwiftSectionTests",
            dependencies: [
                "MachOSwiftSection",
            ]
        ),

        .testTarget(
            name: "DemangleTests",
            dependencies: [
                "Demangle",
            ]
        ),

        .testTarget(
            name: "SwiftDumpTests",
            dependencies: [
                "SwiftDump",
            ]
        ),
    ]
)
