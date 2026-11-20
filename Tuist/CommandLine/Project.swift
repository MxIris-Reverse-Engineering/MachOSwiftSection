import ProjectDescription

// What Tuist cannot convert from ../../Package.swift (Documentations/Internal/TuistDevelopment.md):
// the swift-section executable, and SwiftSectionCommandTests, which imports the executable's module
// (`@testable import swift_section`). Tuist converts no executable target and rejects a test that
// depends on one, so Package.swift leaves that test out while Tuist resolves it and it is described
// here instead. swift_section compiles the command's sources as a static framework for the test; the
// tool compiles them again, so its link needs no trick around the @main entry point.
//
// The dependency list mirrors the swift-section target in Package.swift and is the one hand-written
// copy in the Tuist description: a dependency added there that is missing here fails to compile.
let commandLineDependencies: [TargetDependency] = [
    .external(name: "SwiftSectionKit"),
    .external(name: "MachOFoundation"),
    .external(name: "SwiftSymbols"),
    .external(name: "SwiftDump"),
    .external(name: "SwiftOutputTransformer"),
    .external(name: "SwiftDeclaration"),
    .external(name: "SwiftIndexing"),
    .external(name: "Semantic"),
    .external(name: "OutputTransformer"),
    .external(name: "ObjCDeclarationRendering"),
    .external(name: "ObjCOutputTransformer"),
    .external(name: "Rainbow"),
    .external(name: "ArgumentParser"),
]

// Tuist builds swift-argument-parser for macOS 12, the minimum that package declares; the package's
// own 10.15 does not reach the executable here the way SwiftPM's build of it does.
let commandLineDeploymentTargets: DeploymentTargets = .macOS("12.0")

let commandLineSources: SourceFilesList = ["../../Sources/Executables/swift-section/**"]

// The link flags Tuist/Package.swift gives the package's test targets, for the same reasons: -ObjC, so
// that the archive members defining Swift types and extensions (protocol conformances among them) are
// loaded, and -force_load of the constructor targets the swift-section executable reaches in
// Package.swift, which TuistScript.sh lists in TUIST_FORCE_LOADS.
let forceLoadedTargetNames: [String] = Environment.forceLoads.getString(default: "")
    .split(separator: ",")
    .compactMap { pair in
        let parts = pair.split(separator: ":").map(String.init)
        return parts.count == 2 && parts[0] == "swift-section" ? parts[1] : nil
    }
let linkFlags: SettingsDictionary = [
    "OTHER_LDFLAGS": .array(["$(inherited)", "-ObjC"] + forceLoadedTargetNames.map { targetName in
        "-Wl,-force_load,$(BUILT_PRODUCTS_DIR)/\(targetName).framework/\(targetName)"
    }),
]

// MACHO_SWIFT_SECTION_SILENT_TEST=1, which Package.swift turns into SILENT_TEST for its test targets;
// TuistScript.sh passes it on as TUIST_SILENT_TEST, the only form a Tuist manifest can read.
let commandTestSettings: Settings = .settings(base: linkFlags.merging(
    Environment.silentTest.getBoolean(default: false) ? ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["$(inherited)", "SILENT_TEST"]] : [:]
) { $1 })

let project = Project(
    name: "MachOSwiftSectionCommandLine",
    // In SwiftPM these targets belong to the MachOSwiftSection package, whose `package` declarations
    // they use (SwiftSectionCommandTests calls SwiftSectionKit's applyTransformersEnablingCommentKinds).
    // Tuist gives the targets it converts SWIFT_PACKAGE_NAME = MachOSwiftSection; these need the same.
    settings: .settings(base: ["SWIFT_PACKAGE_NAME": "MachOSwiftSection"]),
    targets: [
        .target(
            name: "swift-section",
            destinations: .macOS,
            product: .commandLineTool,
            // Tuist would name the executable swift_section, as it turns every dash of a target's name
            // into an underscore.
            productName: "swift-section",
            bundleId: "com.machoswiftsection.swift-section",
            deploymentTargets: commandLineDeploymentTargets,
            sources: commandLineSources,
            dependencies: commandLineDependencies,
            settings: .settings(base: linkFlags)
        ),
        .target(
            name: "swift_section",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "com.machoswiftsection.swift-section.module",
            deploymentTargets: commandLineDeploymentTargets,
            sources: commandLineSources,
            dependencies: commandLineDependencies
        ),
        .target(
            name: "SwiftSectionCommandTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.machoswiftsection.SwiftSectionCommandTests",
            deploymentTargets: .macOS("14.0"),
            sources: ["../../Tests/SwiftSectionCommandTests/**"],
            dependencies: [
                .target(name: "swift_section"),
                .external(name: "SwiftDeclarationRendering"),
                .external(name: "SwiftPrinting"),
            ] + commandLineDependencies,
            settings: commandTestSettings
        ),
    ]
)
