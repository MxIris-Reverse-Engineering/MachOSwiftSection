// swift-tools-version: 6.2
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

let MachOKitVersion: Version = "0.39.0"

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
        exact: MachOKitVersion
    )

    static let MachOKitMain = Package.Dependency.package(
        url: "https://github.com/MxIris-Reverse-Engineering/MachOKit",
        branch: "main"
    )

    static let MachOKitSPM = Package.Dependency.package(
        url: "https://github.com/p-x9/MachOKit-SPM",
        from: MachOKitVersion
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
    static let SwiftParser = Target.Dependency.product(
        name: "SwiftParser",
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
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(
            name: "MachOSwiftSection",
            targets: ["MachOSwiftSection"]
        ),
        .library(
            name: "SwiftDump",
            targets: ["SwiftDump"]
        ),
        .library(
            name: "SwiftInterface",
            targets: ["SwiftInterface"]
        ),
        .library(
            name: "TypeIndexing",
            targets: ["TypeIndexing"]
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
        .package(url: "https://github.com/Mx-Iris/FrameworkToolbox", branch: "main"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.2.0"),
        .package(url: "https://github.com/MxIris-Library-Forks/swift-memberwise-init-macro", from: "0.5.3-fork"),
        .package(url: "https://github.com/p-x9/MachOObjCSection", from: "0.4.0"),
        .package(url: "https://github.com/Mx-Iris/SourceKitD", branch: "main"),
        .package(url: "https://github.com/christophhagen/BinaryCodable", from: "3.1.0"),
        .package(url: "https://github.com/MxIris-DeveloperTool-Forks/swift-apinotes", branch: "main"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.4"),
        .package(url: "https://github.com/brightdigit/SyntaxKit", branch: "main"),
//        .package(url: "https://github.com/MxIris-DeveloperTool-Forks/swift-clang", from: "0.1.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.4"),
        .package(url: "https://github.com/MxIris-Reverse-Engineering/DyldPrivate", branch: "main"),
    ],
    targets: [
        .target(
            name: "Semantic"
        ),

        .target(
            name: "Demangling",
            dependencies: [
                "Utilities",
            ]
        ),

        .target(
            name: "Utilities",
            dependencies: [
                "MachOMacros",
                .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
                .product(name: "AssociatedObject", package: "AssociatedObject"),
                .product(name: "MemberwiseInit", package: "swift-memberwise-init-macro"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ]
        ),

        .target(
            name: "MachOExtensions",
            dependencies: [
                .MachOKit,
                "Utilities",
            ]
        ),

        .target(
            name: "MachOCaches",
            dependencies: [
                .MachOKit,
                "MachOExtensions",
                "Utilities",
            ]
        ),

        .target(
            name: "MachOReading",
            dependencies: [
                .MachOKit,
                "Utilities",
                "MachOExtensions",
                .product(name: "FileIO", package: "swift-fileio"),
            ]
        ),

        .target(
            name: "MachOResolving",
            dependencies: [
                .MachOKit,
                "MachOExtensions",
                "MachOReading",
            ]
        ),

        .target(
            name: "MachOSymbols",
            dependencies: [
                .MachOKit,
                "MachOReading",
                "MachOResolving",
                "Demangling",
                "Utilities",
                "MachOCaches",
            ],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-enable-private-imports"]),
            ]
        ),

        .target(
            name: "MachOPointers",
            dependencies: [
                .MachOKit,
                "MachOReading",
                "MachOResolving",
                "Utilities",
            ]
        ),

        .target(
            name: "MachOSymbolPointers",
            dependencies: [
                .MachOKit,
                "MachOReading",
                "MachOResolving",
                "MachOPointers",
                "MachOSymbols",
                "Utilities",
            ]
        ),

        .target(
            name: "MachOFoundation",
            dependencies: [
                .MachOKit,
                "MachOReading",
                "MachOExtensions",
                "MachOPointers",
                "MachOSymbols",
                "MachOResolving",
                "MachOSymbolPointers",
                "Utilities",
            ]
        ),

        .target(
            name: "MachOSwiftSection",
            dependencies: [
                .MachOKit,
                "MachOFoundation",
                "Demangling",
                "Utilities",
                .product(name: "DyldPrivate", package: "DyldPrivate"),
            ],
        ),

        .target(
            name: "SwiftDump",
            dependencies: [
                .MachOKit,
                "MachOSwiftSection",
                "Semantic",
                "Utilities",
                .product(name: "MachOObjCSection", package: "MachOObjCSection"),
            ]
        ),

        .target(
            name: "TypeIndexing",
            dependencies: [
                "SwiftInterface",
                "Utilities",
                .SwiftSyntax,
                .SwiftParser,
                .SwiftSyntaxBuilder,
                .product(name: "SourceKitD", package: "SourceKitD", condition: .when(platforms: [.macOS])),
                .product(name: "BinaryCodable", package: "BinaryCodable"),
                .product(name: "APINotes", package: "swift-apinotes", condition: .when(platforms: [.macOS])),
                .product(name: "MachOObjCSection", package: "MachOObjCSection"),
            ]
        ),

        .target(
            name: "SwiftIndex",
            dependencies: [
                .MachOKit,
                "MachOSwiftSection",
                "SwiftDump",
                "Semantic",
                "Utilities",
            ]
        ),

        .target(
            name: "SwiftInterface",
            dependencies: [
                .MachOKit,
                "MachOSwiftSection",
                "SwiftDump",
                "Semantic",
                "Utilities",
            ]
        ),

        .executableTarget(
            name: "swift-section",
            dependencies: [
                "SwiftDump",
                "SwiftInterface",
                .product(name: "Rainbow", package: "Rainbow"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        // MARK: - Macros

        .macro(
            name: "MachOMacros",
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
            name: "DemanglingTests",
            dependencies: [
                "Demangling",
            ],
            swiftSettings: testSettings
        ),
        .testTarget(
            name: "MachOSymbolsTests",
            dependencies: [
                "MachOSymbols",
                "MachOTestingSupport",
            ],
            swiftSettings: testSettings
        ),
        .testTarget(
            name: "MachOSwiftSectionTests",
            dependencies: [
                "MachOSwiftSection",
                "MachOTestingSupport",
                "SwiftDump",
            ],
            swiftSettings: testSettings
        ),

        .testTarget(
            name: "SwiftDumpTests",
            dependencies: [
                "SwiftDump",
                "MachOTestingSupport",
                .product(name: "MachOObjCSection", package: "MachOObjCSection"),
            ],
            swiftSettings: testSettings
        ),

        .testTarget(
            name: "TypeIndexingTests",
            dependencies: [
                "TypeIndexing",
                "MachOTestingSupport",
            ],
            swiftSettings: testSettings
        ),

        .testTarget(
            name: "SwiftInterfaceTests",
            dependencies: [
                "SwiftInterface",
                "MachOTestingSupport",
            ],
            swiftSettings: testSettings
        ),
    ]
)
