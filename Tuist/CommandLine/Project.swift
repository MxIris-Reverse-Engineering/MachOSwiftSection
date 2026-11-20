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

// MACHO_SWIFT_SECTION_SILENT_TEST=1, which Package.swift turns into SILENT_TEST for its test targets;
// TuistScript.sh passes it on as TUIST_SILENT_TEST, the only form a Tuist manifest can read.
let commandTestSettings: Settings = Environment.silentTest.getBoolean(default: false)
    ? .settings(base: ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["$(inherited)", "SILENT_TEST"]])
    : .settings()

let project = Project(
    name: "MachOSwiftSectionCommandLine",
    targets: [
        .target(
            name: "swift-section",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.machoswiftsection.swift-section",
            deploymentTargets: commandLineDeploymentTargets,
            sources: commandLineSources,
            dependencies: commandLineDependencies
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
