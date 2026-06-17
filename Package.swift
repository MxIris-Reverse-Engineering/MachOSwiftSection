// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

@preconcurrency import PackageDescription
import CompilerPluginSupport
import Foundation

let localEnvironment: [String: String] = {
    let localEnvironmentFilePath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent(".package.env")
        .path
    guard FileManager.default.fileExists(atPath: localEnvironmentFilePath),
          let contents = try? String(contentsOfFile: localEnvironmentFilePath, encoding: .utf8)
    else {
        return [:]
    }
    var environment: [String: String] = [:]
    for line in contents.components(separatedBy: .newlines) {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
            continue
        }
        let parts = trimmedLine.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let value = parts[1].trimmingCharacters(in: .whitespaces)
        environment[key] = value
    }
    return environment
}()

func envEnable(_ key: String, default defaultValue: Bool = false) -> Bool {
    let value = localEnvironment[key] ?? Context.environment[key]
    guard let value else {
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

let usingLocalDependencies = envEnable("USING_LOCAL_DEPENDENCIES")

extension Package.Dependency {
    enum LocalSearchPath {
        case package(path: String, isRelative: Bool, isEnabled: Bool = usingLocalDependencies, traits: Set<PackageDescription.Package.Dependency.Trait> = [.defaults])
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
            case .package(let path, let isRelative, let isEnabled, let traits):
                guard isEnabled else { continue }
                let url = if isRelative {
                    URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: currentFilePath))
                } else {
                    URL(fileURLWithPath: path)
                }

                if FileManager.default.fileExists(atPath: url.path) {
                    return .package(path: url.path, traits: traits)
                }
            }
        }
        return remote
    }
}

let MachOKitVersion: Version = "0.46.1"

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
    .Demangling,
    .Semantic,

    .package(url: "https://github.com/swiftlang/swift-syntax.git", "509.1.0" ..< "604.0.0"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.4"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.1"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.2.0"),

    .package(url: "https://github.com/p-x9/AssociatedObject", from: "0.13.0"),
    .package(url: "https://github.com/p-x9/swift-fileio.git", from: "0.9.0"),
    .package(url: "https://github.com/Mx-Iris/FrameworkToolbox", from: "0.4.0"),

    .package(url: "https://github.com/gohanlon/swift-memberwise-init-macro", from: "0.6.0"),

    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.4"),
    
    // CLI
    .package(url: "https://github.com/onevcat/Rainbow", from: "4.0.0"),

    // Testing
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.9"),
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
        exact: MachOKitVersion,
    )

    static let MachOKitSPM = Package.Dependency.package(
        url: "https://github.com/p-x9/MachOKit-SPM.git",
        from: MachOKitVersion,
    )

    static let MachOKitMain = Package.Dependency.package(
        local: .package(
            path: "../MachOKit",
            isRelative: true,
        ),
        remote: .package(
            url: "https://github.com/MxIris-Reverse-Engineering/MachOKit.git",
            from: "0.46.100",
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
        from: "0.6.0",
    )

    static let MachOObjCSectionMain = Package.Dependency.package(
        local: .package(
            path: "../MachOObjCSection",
            isRelative: true,
        ),
        remote: .package(
            url: "https://github.com/MxIris-Reverse-Engineering/MachOObjCSection.git",
            from: "0.6.100",
        ),
    )
}

extension Package.Dependency {
    static let Demangling = Package.Dependency.package(
        local: .package(
            path: "../swift-demangling",
            isRelative: true,
        ),
        remote: .package(
            url: "https://github.com/MxIris-Reverse-Engineering/swift-demangling",
            from: "0.4.0",
        ),
    )

    static let Semantic = Package.Dependency.package(
        local: .package(
            path: "../swift-semantic-string",
            isRelative: true,
        ),
        remote: .package(
            url: "https://github.com/MxIris-Reverse-Engineering/swift-semantic-string",
            exact: "0.1.1",
        ),
    )
}

extension Target.Dependency {
    static let MachOKit = Target.Dependency.product(
        name: "MachOKit",
        package: "MachOKit",
    )
    static let MachOObjCSection = Target.Dependency.product(
        name: "MachOObjCSection",
        package: "MachOObjCSection",
    )
    static let MachOKitMain = Target.Dependency.product(
        name: "MachOKit",
        package: "MachOKit",
    )
    static let MachOKitSPM = Target.Dependency.product(
        name: "MachOKit",
        package: "MachOKit-SPM",
    )
    static let Demangling = Target.Dependency.product(
        name: "Demangling",
        package: "swift-demangling",
    )
    static let Semantic = Target.Dependency.product(
        name: "Semantic",
        package: "swift-semantic-string",
    )
    static let SwiftSyntax = Target.Dependency.product(
        name: "SwiftSyntax",
        package: "swift-syntax",
    )
    static let SwiftParser = Target.Dependency.product(
        name: "SwiftParser",
        package: "swift-syntax",
    )
    static let SwiftSyntaxMacros = Target.Dependency.product(
        name: "SwiftSyntaxMacros",
        package: "swift-syntax",
    )
    static let SwiftCompilerPlugin = Target.Dependency.product(
        name: "SwiftCompilerPlugin",
        package: "swift-syntax",
    )
    static let SwiftSyntaxMacrosTestSupport = Target.Dependency.product(
        name: "SwiftSyntaxMacrosTestSupport",
        package: "swift-syntax",
    )
    static let SwiftSyntaxBuilder = Target.Dependency.product(
        name: "SwiftSyntaxBuilder",
        package: "swift-syntax",
    )
    static let SwiftTUI = Target.Dependency.product(
        name: "SwiftTUI",
        package: "SwiftTUI",
    )
    static let TermKit = Target.Dependency.product(
        name: "TermKit",
        package: "TermKit",
    )
}

@MainActor
extension Target {
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
        ],
    )

    static let MachOExtensions = Target.target(
        name: "MachOExtensions",
        dependencies: [
            .product(.MachOKit),
            .target(.Utilities),
        ],
    )

    static let MachOCaches = Target.target(
        name: "MachOCaches",
        dependencies: [
            .product(.MachOKit),
            .target(.MachOExtensions),
            .target(.Utilities),
        ],
    )

    static let MachOReading = Target.target(
        name: "MachOReading",
        dependencies: [
            .product(.MachOKit),
            .target(.MachOExtensions),
            .target(.Utilities),
            .product(name: "FileIO", package: "swift-fileio"),
        ],
    )

    static let MachOResolving = Target.target(
        name: "MachOResolving",
        dependencies: [
            .product(.MachOKit),
            .target(.MachOExtensions),
            .target(.MachOReading),
        ],
    )

    static let MachOSymbols = Target.target(
        name: "MachOSymbols",
        dependencies: [
            .product(.MachOKit),
            .product(.Demangling),
            .target(.MachOReading),
            .target(.MachOResolving),
            .target(.Utilities),
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
        ],
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
        ],
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
        ],
    )

    static let MachOSwiftSectionC = Target.target(
        name: "MachOSwiftSectionC",
    )

    static let MachOSwiftSection = Target.target(
        name: "MachOSwiftSection",
        dependencies: [
            .product(.MachOKit),
            .product(.Demangling),
            .target(.MachOFoundation),
            .target(.MachOSwiftSectionC),
            .target(.Utilities),
        ],
    )

    static let SwiftInspection = Target.target(
        name: "SwiftInspection",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .target(.MachOSwiftSection),
            .target(.Utilities),
        ],
    )

    /// Low-level Swift declaration rendering engine extracted from `SwiftDump`:
    /// pure `Keyword`/`Node`/`SemanticString`/`String` extensions, the
    /// `DemangleResolver`, the render configuration, the header-rendering
    /// helpers, and the field-metadata comment engine. Shared by both the
    /// raw-descriptor dump path (`SwiftDump`) and the model-driven interface
    /// path (`SwiftPrinting`), so neither has to depend on the other.
    static let SwiftDeclarationRendering = Target.target(
        name: "SwiftDeclarationRendering",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .target(.MachOSwiftSection),
            .target(.Utilities),
            .target(.SwiftInspection),
        ],
    )

    static let SwiftDump = Target.target(
        name: "SwiftDump",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .target(.MachOSwiftSection),
            .target(.Utilities),
            .target(.SwiftInspection),
            .target(.SwiftDeclarationRendering),
        ],
    )

    /// Shared declaration model: `TypeDefinition`, `ProtocolDefinition`,
    /// `ExtensionDefinition`, names, kinds, and `DefinitionBuilder`. Consumed by
    /// both `SwiftIndexing` (which populates it) and `SwiftPrinting` (which
    /// renders it), keeping those two peers that never depend on each other.
    static let SwiftDeclaration = Target.target(
        name: "SwiftDeclaration",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftDeclarationRendering),
            .target(.Utilities),
        ],
    )

    /// Builds the `SwiftDeclaration` model from a Mach-O image:
    /// `SwiftDeclarationIndexer`, its events/configuration, and the
    /// `GenericSpecializer` analysis built on top of the index.
    static let SwiftIndexing = Target.target(
        name: "SwiftIndexing",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.Utilities),
            .target(.SwiftDeclaration),
        ],
    )

    /// Infers source-level Swift attributes (`@propertyWrapper`,
    /// `@resultBuilder`, `@dynamicMemberLookup`, `@objc`, …) from the
    /// `SwiftDeclaration` model. A low-level peer over the model so the
    /// inference can be reused independently of printing.
    static let SwiftAttributeInference = Target.target(
        name: "SwiftAttributeInference",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.Utilities),
            .target(.SwiftDeclaration),
        ],
    )

    /// Diffs the Swift ABI of two indexed modules. Keys every declaration on
    /// its remangled `Node` and computes a recursive set difference; a pure
    /// peer over the model (no Mach-O), so it only needs `SwiftDeclaration`
    /// and `Demangling`.
    static let SwiftDiffing = Target.target(
        name: "SwiftDiffing",
        dependencies: [
            .product(.Demangling),
            .target(.SwiftDeclaration),
        ],
    )

    /// Renders the `SwiftDeclaration` model as Swift source:
    /// `SwiftDeclarationPrinter`, the node printers/printables, and the
    /// print configuration. Consumes `SwiftAttributeInference` for the
    /// attribute annotations.
    static let SwiftPrinting = Target.target(
        name: "SwiftPrinting",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftDeclarationRendering),
            .target(.Utilities),
            .target(.SwiftDeclaration),
            .target(.SwiftAttributeInference),
        ],
    )

    /// Runtime generic-specialization engine (`GenericSpecializer`,
    /// `ConformanceProvider`). Sits above `SwiftIndexing` because it queries a
    /// populated index to resolve candidates and conformances; kept out of
    /// `SwiftIndexing` so the index can be built and consumed without pulling
    /// in the runtime specialization machinery.
    static let SwiftSpecialization = Target.target(
        name: "SwiftSpecialization",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.Utilities),
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
        ],
    )

    /// Orchestrator: `SwiftInterfaceBuilder` ties indexing and printing
    /// together into a full interface dump.
    static let SwiftInterface = Target.target(
        name: "SwiftInterface",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftDeclarationRendering),
            .target(.Utilities),
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftSpecialization),
            .target(.SwiftDiffing),
        ],
    )

//    static let TypeIndexing = Target.target(
//        name: "TypeIndexing",
//        dependencies: [
//            .target(.SwiftInterface),
//            .target(.Utilities),
//            .product(.SwiftSyntax),
//            .product(.SwiftParser),
//            .product(.SwiftSyntaxBuilder),
//            .product(.MachOObjCSection),
//            .product(name: "Clang", package: "swift-clang"),
//            .product(name: "SourceKitD", package: "SourceKitD", condition: .when(platforms: [.macOS])),
//            .product(name: "BinaryCodable", package: "BinaryCodable"),
//            .product(name: "APINotes", package: "swift-apinotes", condition: .when(platforms: [.macOS])),
//        ]
//    )

    static let swift_section = Target.executableTarget(
        name: "swift-section",
        dependencies: [
            .target(.SwiftDump),
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftDiffing),
            .target(.SwiftInterface),
            .product(name: "Rainbow", package: "Rainbow"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ],
    )

    static let baseline_generator = Target.executableTarget(
        name: "baseline-generator",
        dependencies: [
            .target(.MachOFixtureSupport),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ],
        swiftSettings: testSettings,
    )

    // MARK: - Plugins

    /// `swift package regen-baselines` — regenerates the auto-generated
    /// `__Baseline__/<File>Baseline.swift` files consumed by the fixture-based
    /// test coverage suites. Replaces the legacy `Scripts/regen-baselines.sh`.
    static let RegenerateBaselinesPlugin = Target.plugin(
        name: "RegenerateBaselinesPlugin",
        capability: .command(
            intent: .custom(
                verb: "regen-baselines",
                description: "Regenerate MachOSwiftSection fixture-test ABI baselines.",
            ),
            permissions: [
                .writeToPackageDirectory(
                    reason: "Writes regenerated baselines under Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/.",
                ),
            ],
        ),
        dependencies: [
            .target(.baseline_generator),
        ],
    )

    // MARK: - Macros

    static let MachOMacros = Target.macro(
        name: "MachOMacros",
        dependencies: [
            .product(.SwiftSyntax),
            .product(.SwiftSyntaxMacros),
            .product(.SwiftCompilerPlugin),
            .product(.SwiftSyntaxBuilder),
        ],
    )

    // MARK: - Testing

    /// Fixture-loading helpers, baseline generators, coverage scanners, and
    /// non-Testing-dependent code. Importable from non-test targets (e.g.
    /// `baseline-generator`) without dragging in `Testing.framework`.
    static let MachOFixtureSupport = Target.target(
        name: "MachOFixtureSupport",
        dependencies: [
            .product(.MachOKit),
            .target(.MachOExtensions),
            .target(.MachOFoundation),
            .target(.MachOReading),
            .target(.MachOResolving),
            .target(.MachOSwiftSectionC),
            .target(.SwiftDump),
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftInterface),
            .target(.MachOTestingSupportC),
            .product(.Demangling),
            .product(.SwiftSyntax),
            .product(.SwiftParser),
            .product(.SwiftSyntaxBuilder),
        ],
        swiftSettings: testSettings,
    )

    /// `swift-testing` base classes (`MachOFileTests`, `MachOImageTests`,
    /// `DyldCacheTests`, `XcodeMachOFileTests`, `MachOSwiftSectionFixtureTests`).
    /// Splitting this out from `MachOFixtureSupport` keeps `Testing.framework`
    /// out of the link line for non-test targets.
    static let MachOTestingSupport = Target.target(
        name: "MachOTestingSupport",
        dependencies: [
            .product(.MachOKit),
            .target(.MachOFoundation),
            .target(.MachOReading),
            .target(.MachOResolving),
            .target(.MachOFixtureSupport),
            .target(.MachOSwiftSection),
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftSpecialization),
            .target(.SwiftInterface),
        ],
        swiftSettings: testSettings,
    )

    static let MachOTestingSupportC = Target.target(
        name: "MachOTestingSupportC",
        dependencies: [
        ],
        swiftSettings: testSettings,
    )

    static let MachOSymbolsTests = Target.testTarget(
        name: "MachOSymbolsTests",
        dependencies: [
            .target(.MachOSymbols),
            .target(.MachOTestingSupport),
            .target(.MachOFixtureSupport),
        ],
        swiftSettings: testSettings,
    )

    static let MachOSwiftSectionTests = Target.testTarget(
        name: "MachOSwiftSectionTests",
        dependencies: [
            .target(.MachOSwiftSection),
            .target(.MachOTestingSupport),
            .target(.MachOFixtureSupport),
            .target(.SwiftDump),
        ],
        swiftSettings: testSettings,
    )

    static let MachOCachesTests = Target.testTarget(
        name: "MachOCachesTests",
        dependencies: [
            .target(.MachOCaches),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftInspectionTests = Target.testTarget(
        name: "SwiftInspectionTests",
        dependencies: [
            .target(.MachOSwiftSection),
            .target(.MachOTestingSupport),
            .target(.MachOFixtureSupport),
            .target(.SwiftInspection),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftDumpTests = Target.testTarget(
        name: "SwiftDumpTests",
        dependencies: [
            .target(.SwiftDump),
            .target(.MachOTestingSupport),
            .target(.MachOFixtureSupport),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        ],
        swiftSettings: testSettings,
    )

//    static let TypeIndexingTests = Target.testTarget(
//        name: "TypeIndexingTests",
//        dependencies: [
//            .target(.TypeIndexing),
//            .target(.MachOTestingSupport),
//            .target(.MachOFixtureSupport),
//        ],
//        swiftSettings: testSettings
//    )

    static let SwiftInterfaceTests = Target.testTarget(
        name: "SwiftInterfaceTests",
        dependencies: [
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftSpecialization),
            .target(.SwiftInterface),
            .target(.MachOTestingSupport),
            .target(.MachOFixtureSupport),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftPrintingTests = Target.testTarget(
        name: "SwiftPrintingTests",
        dependencies: [
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.MachOTestingSupport),
            .target(.MachOFixtureSupport),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftAttributeInferenceTests = Target.testTarget(
        name: "SwiftAttributeInferenceTests",
        dependencies: [
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftAttributeInference),
            .target(.MachOTestingSupport),
            .target(.MachOFixtureSupport),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftDiffingTests = Target.testTarget(
        name: "SwiftDiffingTests",
        dependencies: [
            .target(.SwiftDeclaration),
            .target(.SwiftDiffing),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftIndexingTests = Target.testTarget(
        name: "SwiftIndexingTests",
        dependencies: [
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftAttributeInference),
            .target(.MachOTestingSupport),
            .target(.MachOFixtureSupport),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftSpecializationTests = Target.testTarget(
        name: "SwiftSpecializationTests",
        dependencies: [
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftSpecialization),
            .target(.MachOTestingSupport),
            .target(.MachOFixtureSupport),
        ],
        swiftSettings: testSettings,
    )

    static let MachOTestingSupportTests = Target.testTarget(
        name: "MachOTestingSupportTests",
        dependencies: [
            .target(.MachOTestingSupport),
            .target(.MachOFixtureSupport),
        ],
        exclude: [
            "Coverage/Fixtures/SampleSource.swift.txt",
            "Coverage/Fixtures/SuiteSampleSource.swift.txt",
        ],
        swiftSettings: testSettings,
    )

    static let IntegrationTests = Target.testTarget(
        name: "IntegrationTests",
        dependencies: [
            .target(.MachOExtensions),
            .target(.MachOCaches),
            .target(.MachOReading),
            .target(.MachOResolving),
            .target(.MachOSymbols),
            .target(.MachOPointers),
            .target(.MachOSymbolPointers),
            .target(.MachOFoundation),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftDump),
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftInterface),
//            .target(.TypeIndexing),
            .target(.MachOTestingSupport),
            .target(.MachOFixtureSupport),
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Demangling),
            .product(.Semantic),
            .product(name: "Dependencies", package: "swift-dependencies"),
        ],
        swiftSettings: testSettings,
    )
}

let package = Package(
    name: "MachOSwiftSection",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .visionOS(.v1)],
    products: [
        .library(.MachOSwiftSection),
        .library(.SwiftInspection),
        .library(.SwiftDeclarationRendering),
        .library(.SwiftDump),
        .library(.SwiftDeclaration),
        .library(.SwiftAttributeInference),
        .library(.SwiftDiffing),
        .library(.SwiftIndexing),
        .library(.SwiftPrinting),
        .library(.SwiftSpecialization),
        .library(.SwiftInterface),
//        .library(.TypeIndexing),
        .executable(.swift_section),
    ],
    dependencies: dependencies,
    targets: [
        // Library
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
        .SwiftDeclarationRendering,
        .SwiftDump,
        .SwiftDeclaration,
        .SwiftAttributeInference,
        .SwiftDiffing,
        .SwiftIndexing,
        .SwiftPrinting,
        .SwiftSpecialization,
        .SwiftInterface,
//        .TypeIndexing,
        .MachOMacros,
        .MachOFixtureSupport,
        .MachOTestingSupport,
        .MachOTestingSupportC,

        // Executable
        .swift_section,
        .baseline_generator,

        // Plugins
        .RegenerateBaselinesPlugin,

        // Testing
//        .MachOSymbolsTests,
        .MachOSwiftSectionTests,
        .MachOCachesTests,
        .SwiftInspectionTests,
        .SwiftDumpTests,
//        .TypeIndexingTests,
        .SwiftPrintingTests,
        .SwiftAttributeInferenceTests,
        .SwiftDiffingTests,
        .SwiftIndexingTests,
        .SwiftSpecializationTests,
        .SwiftInterfaceTests,
        .MachOTestingSupportTests,
        .IntegrationTests,
    ],
)

extension SwiftSetting {
    static let existentialAny: Self = .enableUpcomingFeature("ExistentialAny") // SE-0335, Swift 5.6,  SwiftPM 5.8+
    static let internalImportsByDefault: Self = .enableUpcomingFeature("InternalImportsByDefault") // SE-0409, Swift 6.0,  SwiftPM 6.0+
    static let memberImportVisibility: Self = .enableUpcomingFeature("MemberImportVisibility") // SE-0444, Swift 6.1,  SwiftPM 6.1+
    static let inferIsolatedConformances: Self = .enableUpcomingFeature("InferIsolatedConformances") // SE-0470, Swift 6.2,  SwiftPM 6.2+
    static let nonisolatedNonsendingByDefault: Self = .enableUpcomingFeature("NonisolatedNonsendingByDefault") // SE-0461, Swift 6.2,  SwiftPM 6.2+
    static let immutableWeakCaptures: Self = .enableUpcomingFeature("ImmutableWeakCaptures") // SE-0481, Swift 6.2,  SwiftPM 6.2+
}
