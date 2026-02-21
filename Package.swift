// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

@preconcurrency import PackageDescription
import CompilerPluginSupport
import Foundation

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

extension Product {
    static func library(_ target: Target) -> Product {
        .library(name: target.name, targets: [target.name])
    }

    static func executable(_ target: Target) -> Product {
        .executable(name: target.name, targets: [target.name])
    }
}

extension Target.Dependency {
    static func target(_ target: Target) -> Self {
        .targetItem(name: target.name, condition: nil)
    }

    static func product(_ dependency: Self) -> Self {
        dependency
    }
}

extension Package.Dependency {
    enum LocalSearchPath {
        case package(path: String, isRelative: Bool, isEnabled: Bool)
    }

    static func package(local localSearchPaths: LocalSearchPath..., remote: Package.Dependency) -> Package.Dependency {
        let currentFilePath = #filePath
        let isClonedDependency = currentFilePath.contains("/checkouts/") ||
            currentFilePath.contains("/SourcePackages/") ||
            currentFilePath.contains("/.build/")

        if isClonedDependency {
            return remote
        }
        for local in localSearchPaths {
            switch local {
            case .package(let path, let isRelative, let isEnabled):
                guard isEnabled else { continue }
                let url = if isRelative {
                    URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: currentFilePath))
                } else {
                    URL(fileURLWithPath: path)
                }

                if FileManager.default.fileExists(atPath: url.path) {
                    return .package(path: url.path)
                }
            }
        }
        return remote
    }
}

let MachOKitVersion: Version = "0.42.0"

let isSilentTest = envEnable("MACHO_SWIFT_SECTION_SILENT_TEST", default: false)

let useSPMPrebuildVersion = envEnable("MACHO_SWIFT_SECTION_USE_SPM_PREBUILD_VERSION", default: false)

let useCustomMachOKit = envEnable("USE_CUSTOM_MACHOKIT", default: true)

let useCustomObjCSection = envEnable("USE_CUSTOM_OBJC_SECTION", default: true)

let useSwiftTUI = envEnable("MACHO_SWIFT_SECTION_USE_SWIFTTUI", default: false)

var testSettings: [SwiftSetting] = []

if isSilentTest {
    testSettings.append(.define("SILENT_TEST"))
}

var dependencies: [Package.Dependency] = [
    .MachOKit,
    .MachOObjCSection,
    
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "509.1.0" ..< "602.0.0"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.4"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.1"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.2.0"),
    
    .package(url: "https://github.com/p-x9/AssociatedObject", from: "0.13.0"),
    .package(url: "https://github.com/p-x9/swift-fileio.git", from: "0.9.0"),
    .package(url: "https://github.com/Mx-Iris/FrameworkToolbox", branch: "main"),
    
    .package(url: "https://github.com/MxIris-Library-Forks/swift-memberwise-init-macro", from: "0.5.3-fork"),
    .package(url: "https://github.com/Mx-Iris/SourceKitD", branch: "main"),
    .package(url: "https://github.com/christophhagen/BinaryCodable", from: "3.1.0"),
    
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.4"),
    .package(url: "https://github.com/MxIris-DeveloperTool-Forks/swift-clang", from: "0.1.0"),
    .package(url: "https://github.com/MxIris-DeveloperTool-Forks/swift-apinotes", branch: "main"),
    .package(url: "https://github.com/MxIris-Reverse-Engineering/DyldPrivate", branch: "main"),
    
    // CLI
    .package(url: "https://github.com/onevcat/Rainbow", from: "4.0.0"),
//    .package(url: "https://github.com/migueldeicaza/TermKit", branch: "main"),
    
    // Testing
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.9"),
    .package(url: "https://github.com/MxIris-Library-Forks/swift-power-assert", branch: "main"),
]

extension Package.Dependency {
    static let MachOKit: Package.Dependency = {
        if useSPMPrebuildVersion {
            return .MachOKitSPM
        } else {
            if useCustomMachOKit {
                return .MachOKitMain
            } else {
                return .MachOKitOrigin
            }
        }
    }()

    static let MachOKitOrigin = Package.Dependency.package(
        url: "https://github.com/p-x9/MachOKit.git",
        exact: MachOKitVersion
    )

    static let MachOKitSPM = Package.Dependency.package(
        url: "https://github.com/p-x9/MachOKit-SPM.git",
        from: MachOKitVersion
    )

    static let MachOKitMain = Package.Dependency.package(
        local: .package(
            path: "../MachOKit",
            isRelative: true,
            isEnabled: true
        ),
        remote: .package(
            url: "https://github.com/MxIris-Reverse-Engineering/MachOKit.git",
            branch: "main"
        ),
    )
}

extension Package.Dependency {
    static let MachOObjCSection: Package.Dependency = {
        if useCustomObjCSection {
            return .MachOObjCSectionMain
        } else {
            return .MachOObjCSectionOrigin
        }
    }()

    static let MachOObjCSectionOrigin = Package.Dependency.package(
        url: "https://github.com/p-x9/MachOObjCSection.git",
        from: "0.5.0"
    )

    static let MachOObjCSectionMain = Package.Dependency.package(
        local: .package(
            path: "../MachOObjCSection",
            isRelative: true,
            isEnabled: true
        ),
        remote: .package(
            url: "https://github.com/MxIris-Reverse-Engineering/MachOObjCSection.git",
            branch: "main"
        ),
    )
}

extension Target.Dependency {
    static let MachOKit = Target.Dependency.product(
        name: "MachOKit",
        package: "MachOKit"
    )

    static let MachOObjCSection = Target.Dependency.product(
        name: "MachOObjCSection",
        package: "MachOObjCSection"
    )

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
    static let SwiftTUI = Target.Dependency.product(
        name: "SwiftTUI",
        package: "SwiftTUI"
    )
    static let TermKit = Target.Dependency.product(
        name: "TermKit",
        package: "TermKit"
    )
}

@MainActor
extension Target {
    static let Semantic = Target.target(
        name: "Semantic"
    )

    static let Demangling = Target.target(
        name: "Demangling",
        dependencies: [
            .target(.Utilities),
        ],
        swiftSettings: [
            .immutableWeakCaptures,
        ]
    )

    static let Utilities = Target.target(
        name: "Utilities",
        dependencies: [
            .target(.MachOMacros),
            .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            .product(name: "AssociatedObject", package: "AssociatedObject"),
            .product(name: "MemberwiseInit", package: "swift-memberwise-init-macro"),
            .product(name: "OrderedCollections", package: "swift-collections"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
        ]
    )

    static let MachOExtensions = Target.target(
        name: "MachOExtensions",
        dependencies: [
            .product(.MachOKit),
            .target(.Utilities),
        ]
    )

    static let MachOCaches = Target.target(
        name: "MachOCaches",
        dependencies: [
            .product(.MachOKit),
            .target(.MachOExtensions),
            .target(.Utilities),
        ]
    )

    static let MachOReading = Target.target(
        name: "MachOReading",
        dependencies: [
            .product(.MachOKit),
            .target(.MachOExtensions),
            .target(.Utilities),
            .product(name: "FileIO", package: "swift-fileio"),
        ]
    )

    static let MachOResolving = Target.target(
        name: "MachOResolving",
        dependencies: [
            .product(.MachOKit),
            .target(.MachOExtensions),
            .target(.MachOReading),
        ]
    )

    static let MachOSymbols = Target.target(
        name: "MachOSymbols",
        dependencies: [
            .product(.MachOKit),
            .target(.MachOReading),
            .target(.MachOResolving),
            .target(.Utilities),
            .target(.Demangling),
            .target(.MachOCaches),
        ],
    )

    static let MachOPointers = Target.target(
        name: "MachOPointers",
        dependencies: [
            .product(.MachOKit),
            .target(.MachOReading),
            .target(.MachOResolving),
            .target(.Utilities),
        ]
    )

    static let MachOSymbolPointers = Target.target(
        name: "MachOSymbolPointers",
        dependencies: [
            .product(.MachOKit),
            .target(.MachOReading),
            .target(.MachOResolving),
            .target(.MachOPointers),
            .target(.MachOSymbols),
            .target(.Utilities),
        ]
    )

    static let MachOFoundation = Target.target(
        name: "MachOFoundation",
        dependencies: [
            .product(.MachOKit),
            .target(.MachOReading),
            .target(.MachOExtensions),
            .target(.MachOPointers),
            .target(.MachOSymbols),
            .target(.MachOResolving),
            .target(.MachOSymbolPointers),
            .target(.Utilities),
        ]
    )

    static let MachOSwiftSectionC = Target.target(
        name: "MachOSwiftSectionC"
    )

    static let MachOSwiftSection = Target.target(
        name: "MachOSwiftSection",
        dependencies: [
            .product(.MachOKit),
            .target(.MachOFoundation),
            .target(.MachOSwiftSectionC),
            .target(.Demangling),
            .target(.Utilities),
            .product(name: "DyldPrivate", package: "DyldPrivate"),
        ]
    )

    static let SwiftInspection = Target.target(
        name: "SwiftInspection",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .target(.MachOSwiftSection),
            .target(.Semantic),
            .target(.Utilities),
        ]
    )

    static let SwiftDump = Target.target(
        name: "SwiftDump",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .target(.MachOSwiftSection),
            .target(.Semantic),
            .target(.Utilities),
            .target(.SwiftInspection),
        ]
    )

    static let SwiftInterface = Target.target(
        name: "SwiftInterface",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftDump),
            .target(.Semantic),
            .target(.Utilities),
        ]
    )

    static let TypeIndexing = Target.target(
        name: "TypeIndexing",
        dependencies: [
            .target(.SwiftInterface),
            .target(.Utilities),
            .product(.SwiftSyntax),
            .product(.SwiftParser),
            .product(.SwiftSyntaxBuilder),
            .product(.MachOObjCSection),
            .product(name: "Clang", package: "swift-clang"),
            .product(name: "SourceKitD", package: "SourceKitD", condition: .when(platforms: [.macOS])),
            .product(name: "BinaryCodable", package: "BinaryCodable"),
            .product(name: "APINotes", package: "swift-apinotes", condition: .when(platforms: [.macOS])),
        ]
    )

    static let swift_section = Target.executableTarget(
        name: "swift-section",
        dependencies: [
            .target(.SwiftDump),
            .target(.SwiftInterface),
            .product(name: "Rainbow", package: "Rainbow"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]
    )

    // MARK: - Macros

    static let MachOMacros = Target.macro(
        name: "MachOMacros",
        dependencies: [
            .product(.SwiftSyntax),
            .product(.SwiftSyntaxMacros),
            .product(.SwiftCompilerPlugin),
            .product(.SwiftSyntaxBuilder),
        ]
    )

    // MARK: - Testing

    static let MachOTestingSupport = Target.target(
        name: "MachOTestingSupport",
        dependencies: [
            .product(.MachOKit),
            .target(.MachOExtensions),
            .target(.SwiftDump),
            .target(.MachOTestingSupportC),
            .product(name: "PowerAssert", package: "swift-power-assert"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        ],
        swiftSettings: testSettings
    )
    
    static let MachOTestingSupportC = Target.target(
        name: "MachOTestingSupportC",
        dependencies: [
        ],
        swiftSettings: testSettings
    )

    static let DemanglingTests = Target.testTarget(
        name: "DemanglingTests",
        dependencies: [
            .target(.Demangling),
        ],
        swiftSettings: testSettings
    )

    static let MachOSymbolsTests = Target.testTarget(
        name: "MachOSymbolsTests",
        dependencies: [
            .target(.MachOSymbols),
            .target(.MachOTestingSupport),
        ],
        swiftSettings: testSettings
    )

    static let MachOSwiftSectionTests = Target.testTarget(
        name: "MachOSwiftSectionTests",
        dependencies: [
            .target(.MachOSwiftSection),
            .target(.MachOTestingSupport),
            .target(.SwiftDump),
        ],
        swiftSettings: testSettings
    )

    static let SwiftInspectionTests = Target.testTarget(
        name: "SwiftInspectionTests",
        dependencies: [
            .target(.MachOSwiftSection),
            .target(.MachOTestingSupport),
            .target(.SwiftInspection),
        ],
        swiftSettings: testSettings
    )

    static let SwiftDumpTests = Target.testTarget(
        name: "SwiftDumpTests",
        dependencies: [
            .target(.SwiftDump),
            .target(.MachOTestingSupport),
            .product(.MachOObjCSection),
        ],
        swiftSettings: testSettings
    )

    static let TypeIndexingTests = Target.testTarget(
        name: "TypeIndexingTests",
        dependencies: [
            .target(.TypeIndexing),
            .target(.MachOTestingSupport),
        ],
        swiftSettings: testSettings
    )

    static let SwiftInterfaceTests = Target.testTarget(
        name: "SwiftInterfaceTests",
        dependencies: [
            .target(.SwiftInterface),
            .target(.MachOTestingSupport),
        ],
        swiftSettings: testSettings
    )

    static let SemanticTests = Target.testTarget(
        name: "SemanticTests",
        dependencies: [
            .target(.Semantic),
        ],
        swiftSettings: testSettings
    )
}

let package = Package(
    name: "MachOSwiftSection",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .visionOS(.v1)],
    products: [
        .library(.MachOSwiftSection),
        .library(.SwiftDump),
        .library(.SwiftInterface),
        .library(.TypeIndexing),
        .executable(.swift_section),
    ],
    dependencies: dependencies,
    targets: [
        // Library
        .Semantic,
        .Demangling,
        .Utilities,
        .MachOExtensions,
        .MachOCaches,
        .MachOReading,
        .MachOResolving,
        .MachOSymbols,
        .MachOPointers,
        .MachOSymbolPointers,
        .MachOFoundation,
        .MachOSwiftSectionC,
        .MachOSwiftSection,
        .SwiftInspection,
        .SwiftDump,
        .SwiftInterface,
        .TypeIndexing,
        .MachOMacros,
        .MachOTestingSupport,
        .MachOTestingSupportC,
        

        // Executable
        .swift_section,

        // Testing
        .DemanglingTests,
        .MachOSymbolsTests,
        .MachOSwiftSectionTests,
        .SwiftInspectionTests,
        .SwiftDumpTests,
        .TypeIndexingTests,
        .SwiftInterfaceTests,
        .SemanticTests,
    ]
)

extension SwiftSetting {
    static let existentialAny: Self = .enableUpcomingFeature("ExistentialAny")                                    // SE-0335, Swift 5.6,  SwiftPM 5.8+
    static let internalImportsByDefault: Self = .enableUpcomingFeature("InternalImportsByDefault")                // SE-0409, Swift 6.0,  SwiftPM 6.0+
    static let memberImportVisibility: Self = .enableUpcomingFeature("MemberImportVisibility")                    // SE-0444, Swift 6.1,  SwiftPM 6.1+
    static let inferIsolatedConformances: Self = .enableUpcomingFeature("InferIsolatedConformances")              // SE-0470, Swift 6.2,  SwiftPM 6.2+
    static let nonisolatedNonsendingByDefault: Self = .enableUpcomingFeature("NonisolatedNonsendingByDefault")    // SE-0461, Swift 6.2,  SwiftPM 6.2+
    static let immutableWeakCaptures: Self = .enableUpcomingFeature("ImmutableWeakCaptures")                      // SE-0481, Swift 6.2,  SwiftPM 6.2+
}
