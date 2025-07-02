// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

@preconcurrency import PackageDescription
import CompilerPluginSupport

func envEnable(_ key: String, default defaultValue: Bool = false) -> Bool {
    guard let value = Context.environment[key] else {
        return defaultValue
    }
    if value == "1" {
        return true
    } else if value == "0" {
        return false
    } else {
        return defaultValue
    }
}

let isSilentTest = envEnable("MACHO_SWIFT_SECTION_SILENT_TEST", default: false)

let useSPMPrebuildVersion = envEnable("MACHO_SWIFT_SECTION_USE_SPM_PREBUILD_VERSION", default: false)

var testSettings: [SwiftSetting] = []

if isSilentTest {
    testSettings.append(.define("SILENT_TEST"))
}

extension Package.Dependency {
    static let MachOKit: Package.Dependency = {
        if useSPMPrebuildVersion {
            return .MachOKitSPM
        } else {
            return .MachOKitOrigin
        }
    }()

    static let MachOKitOrigin = Package.Dependency.package(
        url: "https://github.com/p-x9/MachOKit.git",
        from: "0.35.1"
    )

    static let MachOKitMain = Package.Dependency.package(
        url: "https://github.com/MxIris-Reverse-Engineering/MachOKit",
        branch: "main"
    )

    static let MachOKitSPM = Package.Dependency.package(
        url: "https://github.com/p-x9/MachOKit-SPM",
        from: "0.35.1"
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
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .visionOS(.v1)],
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
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "509.1.0" ..< "602.0.0"),
        .package(url: "https://github.com/p-x9/AssociatedObject", from: "0.13.0"),
        .package(url: "https://github.com/p-x9/swift-fileio.git", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.1"),
        .package(url: "https://github.com/onevcat/Rainbow", from: "4.0.0"),
        .package(url: "https://github.com/Mx-Iris/FrameworkToolbox", from: "0.3.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.2.0"),
        .package(url: "https://github.com/MxIris-Library-Forks/swift-memberwise-init-macro", from: "0.5.3-fork"),
    ],
    targets: [
        .target(
            name: "Semantic"
        ),

        .target(
            name: "Demangle",
            dependencies: [
                .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            ]
        ),

        .target(
            name: "Utilities"
        ),

        .target(
            name: "MachOExtensions",
            dependencies: [
                .MachOKit,
                "MachOMacro",
                .product(name: "AssociatedObject", package: "AssociatedObject"),
            ]
        ),

        .target(
            name: "MachOCaches",
            dependencies: [
                .MachOKit,
                "MachOExtensions",
                "MachOMacro",
                "Utilities",
                .product(name: "AssociatedObject", package: "AssociatedObject"),
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
            name: "MachOSymbols",
            dependencies: [
                .MachOKit,
                "MachOReading",
                "MachOMacro",
                "Demangle",
                "Utilities",
                .product(name: "OrderedCollections", package: "swift-collections"),
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
                "MachOSymbols",
            ]
        ),

        .target(
            name: "MachOSwiftSection",
            dependencies: [
                .MachOKit,
                "Demangle",
                "MachOFoundation",
                "MachOMacro",
                .product(name: "MemberwiseInit", package: "swift-memberwise-init-macro"),
            ]
        ),

        .target(
            name: "SwiftDump",
            dependencies: [
                .MachOKit,
                "MachOSwiftSection",
                "Semantic",
                "Utilities",
                .product(name: "OrderedCollections", package: "swift-collections"),
            ]
        ),

        .executableTarget(
            name: "swift-section",
            dependencies: [
                "SwiftDump",
                .product(name: "Rainbow", package: "Rainbow"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        // MARK: - Macros

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

        // MARK: - Testing

        .target(
            name: "MachOTestingSupport",
            dependencies: [
                .MachOKit,
                "MachOExtensions",
                "SwiftDump",
            ],
            swiftSettings: testSettings
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
            ],
            swiftSettings: testSettings
        ),

        .testTarget(
            name: "SwiftDumpTests",
            dependencies: [
                "SwiftDump",
                "MachOTestingSupport",
            ],
            swiftSettings: testSettings
        ),
    ],
    swiftLanguageModes: [.v5]
)
