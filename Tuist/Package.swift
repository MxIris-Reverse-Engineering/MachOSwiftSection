// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The dependencies of MachOSwiftSection-Tuist.xcworkspace, the development-only Tuist workspace
// (Documentations/Internal/TuistDevelopment.md). Generate it with ./TuistScript.sh, never with a bare
// `tuist generate`: the script sets the variables everything below reads.
//
// MachOSwiftSection itself is declared by path, so its Package.swift stays the only definition of its
// targets and dependencies. In the local dependency mode (`./TuistScript.sh <command>
// --local-dependencies`) the script names the upstream packages the native workspace lists beside
// the checkout in TUIST_LOCAL_PACKAGE_NAMES and the directory holding them in
// TUIST_LOCAL_PACKAGE_CHECKOUTS. A root's path dependency stands in for every other declaration of the
// same package in the graph — MachOSwiftSection's URLs and the upstream packages' own — so they build
// from those checkouts, uncommitted edits included. A path package's identity is its directory's name.
let processEnvironment = ProcessInfo.processInfo.environment
let localPackageCheckoutsDirectory = processEnvironment["TUIST_LOCAL_PACKAGE_CHECKOUTS"] ?? ""
let localPackageNames = (processEnvironment["TUIST_LOCAL_PACKAGE_NAMES"] ?? "")
    .split(separator: ",")
    .map(String.init)
// Qualified: Tuist evaluates this file with ProjectDescription imported too, which has a Package of
// its own.
let localPackageDependencies: [PackageDescription.Package.Dependency] = localPackageCheckoutsDirectory.isEmpty
    ? []
    : localPackageNames.map { packageName in .package(path: "\(localPackageCheckoutsDirectory)/\(packageName)") }

#if TUIST
    import ProjectDescription

    func targetNames(in variable: String) -> [String] {
        (processEnvironment[variable] ?? "").split(separator: ",").map(String.init)
    }

    // Tuist suppresses warnings in every package; Xcode does so for remote packages only. The targets
    // of the packages declared by path get theirs back: MachOSwiftSection always, the upstream
    // packages in the local dependency mode.
    let warningSettings: [String: Settings] = Dictionary(
        targetNames(in: "TUIST_WARNING_TARGET_NAMES").map { targetName in
            (targetName, Settings.settings(base: ["SWIFT_SUPPRESS_WARNINGS": "NO", "GCC_WARN_INHIBIT_ALL_WARNINGS": "NO"]))
        },
        uniquingKeysWith: { first, _ in first }
    )

    // Tuist drops a package setting whose only condition is a trait. MachOSwiftSection enables
    // swift-capstone's AARCH64 trait, which defines CAPSTONE_HAS_AARCH64 for both the Swift wrapper and
    // the C library that way. Without it the wrapper does not compile, and the C library would compile
    // but support no architecture at all.
    let restatedTraitDefinitions: [String: Settings] = [
        "Capstone": .settings(base: [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["$(inherited)", "CAPSTONE_HAS_AARCH64"],
            "GCC_PREPROCESSOR_DEFINITIONS": ["$(inherited)", "CAPSTONE_HAS_AARCH64=1"],
        ]),
        "Ccapstone": .settings(base: [
            "GCC_PREPROCESSOR_DEFINITIONS": ["$(inherited)", "CAPSTONE_HAS_AARCH64=1"],
        ]),
    ]

    // A library target that imports Testing, such as a package's testing support, uses Swift Testing's
    // macros (#expect, #require). Xcode points only test targets at the toolchain's TestingMacros
    // plugin; SwiftPM gives it to every target. TUIST_TESTING_SUPPORT_TARGET_NAMES lists the library
    // targets whose sources import Testing.
    let testingSupportSettings: [String: Settings] = Dictionary(
        targetNames(in: "TUIST_TESTING_SUPPORT_TARGET_NAMES").map { targetName in
            (targetName, Settings.settings(base: [
                "ENABLE_TESTING_SEARCH_PATHS": "YES",
                "OTHER_SWIFT_FLAGS": ["$(inherited)", "-plugin-path", "$(TOOLCHAIN_DIR)/usr/lib/swift/host/plugins/testing"],
            ]))
        },
        uniquingKeysWith: { first, _ in first }
    )

    // The test targets, which SwiftPM builds and links differently in three ways:
    // - It builds a test target for at least the macOS version XCTest and Swift Testing require (14.0
    //   with Xcode 26 and 27), whatever its package declares; Tuist takes the package's own minimum, and
    //   MachOSwiftSection's 10.15 leaves TypeIndexingTests without the macOS 13 APIs it tests.
    // - It links each package target's object files whole, where Tuist links static frameworks and the
    //   linker loads only the archive members something refers to by symbol. A protocol conformance
    //   nothing names goes missing, and `as?` fails without a word: the readers that wrap a MachOImage
    //   or MachOFile (MachOReaderWrapper) read as neither. -ObjC also loads every member that defines an
    //   Objective-C class or category or a Swift type or extension (Xcode 27's linker), as it does for
    //   RuntimeViewer's Tuist workspace.
    // - A load-time constructor nothing refers to never runs that way at all: MachOSwiftSection's
    //   SwiftSymbolsRegistration registers Swift as a symbol language from one. TUIST_FORCE_LOADS pairs
    //   each final link with the constructor targets its in-package dependencies reach, as
    //   "<linking target>:<constructor target>,…"; those archives are loaded whole.
    // TUIST_TEST_TARGET_NAMES lists every mapped test target, IntegrationTests included, so that a build
    // of the whole workspace compiles and links too. Tuist/CommandLine/Project.swift gives the
    // swift-section executable and SwiftSectionCommandTests the same link flags.
    let forceLoadedTargetsByLinkingTarget: [String: [String]] = Dictionary(
        targetNames(in: "TUIST_FORCE_LOADS").compactMap { pair -> (String, [String])? in
            let parts = pair.split(separator: ":").map(String.init)
            return parts.count == 2 ? (parts[0], [parts[1]]) : nil
        },
        uniquingKeysWith: +
    )
    let testTargetSettings: [String: Settings] = Dictionary(
        targetNames(in: "TUIST_TEST_TARGET_NAMES").map { targetName in
            let forceLoadFlags = (forceLoadedTargetsByLinkingTarget[targetName] ?? []).map { loadedTarget in
                "-Wl,-force_load,$(BUILT_PRODUCTS_DIR)/\(loadedTarget).framework/\(loadedTarget)"
            }
            return (targetName, Settings.settings(base: [
                "MACOSX_DEPLOYMENT_TARGET": "14.0",
                "OTHER_LDFLAGS": .array(["$(inherited)", "-ObjC"] + forceLoadFlags),
            ]))
        },
        uniquingKeysWith: { first, _ in first }
    )

    // One target may need several of the settings above; their keys never overlap.
    func mergingSettings(_ settingsByTarget: [String: Settings]...) -> [String: Settings] {
        settingsByTarget.reduce(into: [:]) { merged, settings in
            merged.merge(settings) { first, second in .settings(base: first.base.merging(second.base) { $1 }) }
        }
    }

    let packageSettings = PackageSettings(
        targetSettings: mergingSettings(warningSettings, restatedTraitDefinitions, testTargetSettings, testingSupportSettings),
        // TuistScript.sh sets the variable to 1 unless a package declared by path still has a test of
        // a shape Tuist rejects (the manifests' TUIST_MAPS_LOCAL_PACKAGE_TESTS block removes them).
        includeLocalPackageTestTargets: processEnvironment["TUIST_MAPS_LOCAL_PACKAGE_TESTS"] == "1"
    )
#endif

let package = Package(
    name: "MachOSwiftSectionTuistDependencies",
    dependencies: [
        .package(path: ".."),
        // Stands in for swift-syntax in every macro package, as it does as a member of the native
        // workspace: SwiftPM matches it by package identity.
        .package(path: "../PrecompiledLibraries/swift-syntax"),
        // Used only by MachOSwiftSection's tests. Tuist maps a test target only when every package
        // its dependencies come from is declared here, with the requirement Package.swift gives it.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.9"),
    ] + localPackageDependencies
)
