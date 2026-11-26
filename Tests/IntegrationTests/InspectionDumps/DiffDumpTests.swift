import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
import SwiftSectionTestingSupport
@testable import MachOSwiftSection
import SwiftDeclarationRendering
@_spi(Support) @testable import SwiftInterface
@_spi(Support) @testable import SwiftIndexing
import SwiftDiffing
import ObjCDiffing
import Semantic

/// The three two-version outputs, each the pipeline of one subcommand.
enum DiffDumpKind: Sendable {
    /// `swift-section diff` and `diff --json`: the change list with the
    /// verdict line (`-Diff.txt`) and its machine-readable form
    /// (`-Diff.json`).
    case swiftReport
    /// `swift-section diff --interface`: the new interface annotated with
    /// inline `+`/`-` markers (`-AnnotatedInterface-Inline.swiftinterface`)
    /// and as a unified diff (`-AnnotatedInterface-Unified.swiftinterface`);
    /// the console prints the inline one.
    case swiftInterface
    /// `swift-section objc diff` and `objc diff --json`: the change list
    /// with the verdict line (`-ObjCDiff.txt`) and its JSON
    /// (`-ObjCDiff.json`). Objective-C has no annotated header for a diff.
    case objcReport

    var language: MetadataLanguage {
        switch self {
        case .swiftReport, .swiftInterface: .swift
        case .objcReport: .objc
        }
    }
}

/// The diff dumps: the first and last version of a version axis — two
/// simulator runtimes, two dyld shared caches, two Xcodes — run through the
/// pipelines of `swift-section diff` and `swift-section objc diff`. A diff
/// reads each version's primary image: neither differ compares groups of
/// images.
///
/// A conforming suite supplies the axis (`VersionAxisDumpTests`), usually by
/// inheriting one of the axis base classes and naming two versions. Like its
/// siblings this is a maintainer-inspection dump: it prints / writes results
/// without assertions.
protocol DiffDumpTests: VersionAxisDumpTests {}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension DiffDumpTests {
    /// Runs one pipeline over the first and last version of this suite's
    /// axis for the pipeline's language, then prints the result, or writes
    /// it named after the new version's image. An axis left with fewer than
    /// two versions carrying the metadata has nothing to compare: the dump
    /// says so and writes nothing.
    func dump(_ kind: DiffDumpKind, to destination: DumpDestination) async throws {
        let axis = versionAxis(for: kind.language)
        guard axis.versions.count >= 2, let oldVersion = axis.versions.first, let newVersion = axis.versions.last else {
            printResult("No diff: \(axis.versions.count) version(s) carry the \(kind.language) metadata")
            return
        }
        let output: DumpOutput
        switch kind {
        case .swiftReport:
            output = try await swiftReport(old: oldVersion, new: newVersion)
        case .swiftInterface:
            output = try await swiftInterface(old: oldVersion, new: newVersion, rendersUnifiedDiff: destination == .file)
        case .objcReport:
            output = try await objcReport(old: oldVersion, new: newVersion)
        }
        try deliver(output, to: destination) { file in
            try write(file.text, forImageGroup: [newVersion.primaryImage], suffix: file.suffix, fileExtension: file.fileExtension)
        }
    }

    // MARK: - Swift

    /// Both primary images indexed in one timed step — the differ needs both
    /// sides before it can compare them, so the printed duration covers the
    /// whole preparation.
    private func preparedBuilders(
        old oldVersion: AxisVersion,
        new newVersion: AxisVersion
    ) async throws -> (old: SwiftDiffableInterfaceBuilder<MachOFile>, new: SwiftDiffableInterfaceBuilder<MachOFile>) {
        let oldBuilder = SwiftDiffableInterfaceBuilder(configuration: indexConfiguration, in: oldVersion.primaryImage.machOFile)
        let newBuilder = SwiftDiffableInterfaceBuilder(configuration: indexConfiguration, in: newVersion.primaryImage.machOFile)
        try await measuringPreparation {
            try await oldBuilder.prepare()
            try await newBuilder.prepare()
        }
        return (oldBuilder, newBuilder)
    }

    /// The change list plus the one-line compatibility verdict, as
    /// `swift-section diff` prints it, and the diff as `diff --json` writes
    /// it.
    private func swiftReport(old oldVersion: AxisVersion, new newVersion: AxisVersion) async throws -> DumpOutput {
        let builders = try await preparedBuilders(old: oldVersion, new: newVersion)
        let diff = ABIDiffer().diff(old: builders.old.abiModule(), new: builders.new.abiModule())
        let verdict = "ABI-breaking: \(diff.hasBreakingChange) · backward-compatible: \(diff.isBackwardCompatible)"
        let report = ABIDiffReporter().report(diff) + "\n\n" + verdict
        return DumpOutput(
            consoleText: report,
            files: [
                DumpFile(suffix: "Diff", fileExtension: "txt", text: report),
                DumpFile(suffix: "Diff", fileExtension: "json", text: String(decoding: try ABIJSON.encoder().encode(diff), as: UTF8.self)),
            ]
        )
    }

    /// The new interface annotated against the old, as `diff --interface`
    /// prints it: with inline markers always, as a unified diff only when it
    /// goes to a file — each form is a full print of its own.
    private func swiftInterface(
        old oldVersion: AxisVersion,
        new newVersion: AxisVersion,
        rendersUnifiedDiff: Bool
    ) async throws -> DumpOutput {
        let builders = try await preparedBuilders(old: oldVersion, new: newVersion)
        let inlineInterface = await SwiftDiffableInterfaceRenderer(old: builders.old, new: builders.new)
            .printAnnotatedInterface(format: .inline)
            .string
        var files = [DumpFile(suffix: "AnnotatedInterface-Inline", fileExtension: "swiftinterface", text: inlineInterface)]
        if rendersUnifiedDiff {
            let unifiedInterface = await SwiftDiffableInterfaceRenderer(old: builders.old, new: builders.new)
                .printAnnotatedInterface(format: .unified())
                .string
            files.append(DumpFile(suffix: "AnnotatedInterface-Unified", fileExtension: "swiftinterface", text: unifiedInterface))
        }
        return DumpOutput(consoleText: inlineInterface, files: files)
    }

    // MARK: - Objective-C

    /// The change list plus the verdict line, as `swift-section objc diff`
    /// prints it, and the diff as `objc diff --json` writes it. Both sides
    /// go through the persisted snapshot form, the way the command line reads
    /// a binary.
    private func objcReport(old oldVersion: AxisVersion, new newVersion: AxisVersion) async throws -> DumpOutput {
        let documents = try await measuringPreparation {
            let oldDocument = try await objcSnapshotDocument(of: oldVersion.primaryImage, label: oldVersion.label)
            let newDocument = try await objcSnapshotDocument(of: newVersion.primaryImage, label: newVersion.label)
            return (old: oldDocument, new: newDocument)
        }
        let diff = ObjCAPIDiffer().diff(old: documents.old, new: documents.new)
        let verdict = "API-breaking: \(diff.hasBreakingChange) · backward-compatible: \(diff.isBackwardCompatible)"
        let report = ObjCAPIDiffReporter().report(diff) + "\n\n" + verdict
        return DumpOutput(
            consoleText: report,
            files: [
                DumpFile(suffix: "ObjCDiff", fileExtension: "txt", text: report),
                DumpFile(suffix: "ObjCDiff", fileExtension: "json", text: String(decoding: try ObjCAPIJSON.encoder().encode(diff), as: UTF8.self)),
            ]
        )
    }
}
