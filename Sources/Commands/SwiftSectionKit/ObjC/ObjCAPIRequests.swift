import Foundation
import MachOKit
import ObjCDiffing
import ObjCIndexing
import ObjCInterface
import ObjCMetadataSource
import SwiftIndexing

/// `swift-section objc snapshot`: index a binary's ObjC API and persist it as a
/// baseline document — or relabel an existing document.
public struct ObjCAPISnapshotRequest: Sendable, Equatable {
    public var source: SnapshotSource
    public var binaryLoading: BinaryLoadingOptions
    /// A human-readable version label stored in the provenance (`26.0`).
    public var label: String?
    public var destination: ProductDestination

    public init(
        source: SnapshotSource,
        binaryLoading: BinaryLoadingOptions = .init(),
        label: String? = nil,
        destination: ProductDestination = .output
    ) {
        self.source = source
        self.binaryLoading = binaryLoading
        self.label = label
        self.destination = destination
    }

    /// Produces the document, delivers its JSON, and returns it.
    @discardableResult
    public func run(output: some SwiftSectionOutput, environment: SwiftSectionEnvironment) async throws -> ObjCAPISnapshotDocument {
        let document = try await ObjCAPISnapshotLoading.loadDocument(
            from: source,
            binaryLoading: binaryLoading,
            label: label,
            output: output,
            environment: environment
        )
        let encoded = try document.encoded()
        switch destination {
        case .output:
            output.write(.data(encoded))
        case .file(let path):
            try encoded.write(to: URL(fileURLWithPath: path), options: .atomic)
            output.reportProgress("Snapshot written to \(path)")
        }
        return document
    }
}

/// `swift-section objc diff`: compare the ObjC API of two binaries, or of a
/// binary and a persisted baseline.
public struct ObjCAPIDiffRequest: Sendable, Equatable {
    public enum Report: Sendable, Hashable {
        /// The change list followed by the verdict line.
        case changeList
        /// The verdict line alone. It goes to the output even when the
        /// destination is a file, as it always has on the command line.
        case summary
        /// The diff with provenance, as JSON.
        case json
    }

    public var old: SnapshotSource
    public var new: SnapshotSource
    public var binaryLoading: BinaryLoadingOptions
    public var report: Report
    public var destination: ProductDestination

    public init(
        old: SnapshotSource,
        new: SnapshotSource,
        binaryLoading: BinaryLoadingOptions = .init(),
        report: Report = .changeList,
        destination: ProductDestination = .output
    ) {
        self.old = old
        self.new = new
        self.binaryLoading = binaryLoading
        self.report = report
        self.destination = destination
    }

    public func run(output: some SwiftSectionOutput, environment: SwiftSectionEnvironment) async throws -> ObjCAPIDiffOutcome {
        let oldDocument = try await ObjCAPISnapshotLoading.loadDocument(from: old, binaryLoading: binaryLoading, label: nil, output: output, environment: environment)
        let newDocument = try await ObjCAPISnapshotLoading.loadDocument(from: new, binaryLoading: binaryLoading, label: nil, output: output, environment: environment)

        output.reportProgress("Diffing…")
        let diff = ObjCAPIDiffer().diff(old: oldDocument, new: newDocument)

        let verdict = "API-breaking: \(diff.hasBreakingChange) · backward-compatible: \(diff.isBackwardCompatible)"
        switch report {
        case .json:
            let encoded = String(decoding: try ObjCAPIJSON.encoder().encode(diff), as: UTF8.self)
            try destination.deliver(encoded, to: output, announcingFileWith: { "Report written to \($0)" })
        case .summary:
            output.write(.text(verdict))
        case .changeList:
            try destination.deliver(ObjCAPIDiffReporter().report(diff) + "\n\n" + verdict, to: output, announcingFileWith: { "Report written to \($0)" })
        }
        return ObjCAPIDiffOutcome(diff: diff)
    }
}

public struct ObjCAPIDiffOutcome: Sendable {
    public var diff: ObjCAPIDiff

    public init(diff: ObjCAPIDiff) {
        self.diff = diff
    }

    public var hasBreakingChange: Bool {
        diff.hasBreakingChange
    }
}

/// `swift-section objc evolution`: track the ObjC API of one binary across an
/// ordered series of versions.
public struct ObjCAPIEvolutionRequest: Sendable, Equatable {
    public enum Report: Sendable, Hashable {
        /// The full lineage report.
        case lineage
        /// The header and the per-transition summary.
        case summary
        /// The evolution as JSON.
        case json
        /// The union header annotated with per-declaration lifecycle
        /// comments, each declaration rendered the way `objc dump` renders
        /// it. Every input must be a binary. `availabilityAttributes` says
        /// whether a lifecycle one availability macro can express is also
        /// spelled as that macro.
        case annotatedInterface(availabilityAttributes: AvailabilityAttributes)
    }

    /// Whether the annotated header also spells lifecycles as availability
    /// macros (`API_AVAILABLE`, `API_OBSOLETED`), and for which platform.
    ///
    /// A declaration gets the macro only when one macro expresses its whole
    /// lifecycle: one unbroken run of versions carrying it, every label
    /// involved a numeric version (`26.0`), and an addition or a removal
    /// inside the axis. Its lifecycle comment stays either way.
    public enum AvailabilityAttributes: Sendable, Hashable {
        /// The lifecycle comments alone.
        case none
        /// For the platform every input's `LC_BUILD_VERSION` names, a
        /// simulator counting as its device. Inputs that name no platform the
        /// availability macros can spell, or different ones, throw
        /// ``ObjCAvailabilityPlatformInferenceError``.
        case inferredPlatform
        /// For this platform, spelled the way the availability macros spell
        /// it: `macos`, `ios`, `macCatalyst`.
        case platform(String)
    }

    /// The inputs in version order, oldest first. They are loaded one after
    /// the other.
    public var inputs: [SnapshotSource]
    /// One label per input for the version axis. `nil` falls back to each
    /// snapshot's stored label, then to the file name.
    public var labels: [String]?
    public var binaryLoading: BinaryLoadingOptions
    public var report: Report
    public var destination: ProductDestination

    public init(
        inputs: [SnapshotSource],
        labels: [String]? = nil,
        binaryLoading: BinaryLoadingOptions = .init(),
        report: Report = .lineage,
        destination: ProductDestination = .output
    ) {
        self.inputs = inputs
        self.labels = labels
        self.binaryLoading = binaryLoading
        self.report = report
        self.destination = destination
    }

    public func run(output: some SwiftSectionOutput, environment: SwiftSectionEnvironment) async throws -> ObjCAPIEvolutionOutcome {
        if let labels, labels.count != inputs.count {
            throw ObjCAPIEvolutionError.labelCountMismatch(labelCount: labels.count, versionCount: inputs.count)
        }
        if case .annotatedInterface(let availabilityAttributes) = report {
            return try await runAnnotatedInterface(availabilityAttributes: availabilityAttributes, output: output)
        }

        var documents: [ObjCAPISnapshotDocument] = []
        for (inputIndex, input) in inputs.enumerated() {
            documents.append(try await ObjCAPISnapshotLoading.loadDocument(
                from: input,
                binaryLoading: binaryLoading,
                label: labels?[inputIndex],
                output: output,
                environment: environment
            ))
        }

        // A snapshot input may already carry a provenance label; a binary
        // falls back to its file name, so that the axis is always readable.
        let resolvedLabels = documents.enumerated().map { inputIndex, document in
            document.provenance?.label ?? inputs[inputIndex].defaultLabel
        }

        output.reportProgress("Tracking evolution…")
        let evolution = try ObjCAPIEvolutionBuilder().evolution(of: documents, labels: resolvedLabels)

        let reportText: String = switch report {
        case .json:
            String(decoding: try ObjCAPIJSON.encoder().encode(evolution), as: UTF8.self)
        case .summary:
            ObjCAPIEvolutionReporter().summary(evolution)
        case .lineage, .annotatedInterface:
            ObjCAPIEvolutionReporter().report(evolution)
        }
        try destination.deliver(
            destination == .output ? reportText : reportText + "\n",
            to: output,
            announcingFileWith: { "Report written to \($0)" }
        )
        return ObjCAPIEvolutionOutcome(evolution: evolution)
    }

    /// The union header with lifecycle annotations, rendered from the live
    /// declarations of every version — which is why snapshot inputs are
    /// rejected, the same constraint as the Swift `evolution --interface`.
    private func runAnnotatedInterface(
        availabilityAttributes: AvailabilityAttributes,
        output: some SwiftSectionOutput
    ) async throws -> ObjCAPIEvolutionOutcome {
        try SnapshotSource.requireBinaries(inputs)

        var machOFiles: [MachOFile] = []
        for input in inputs {
            output.reportProgress("Loading \(input.path)…")
            machOFiles.append(try binaryLoading.machOSource(forBinaryAt: input.path).load())
        }
        // Before indexing, so that a platform that cannot be inferred costs
        // only the loading.
        _ = try availabilityAttributes.platform(forInputsAt: inputs.map(\.path), loadedAs: machOFiles)

        // Step 2 of the objc-evolution-interface proposal hands each version
        // to MachOObjCSection's evolution header renderer here.
        throw ObjCAnnotatedHeaderRendererUnavailableError()
    }
}

/// Thrown by an annotated `objc evolution` until MachOObjCSection's evolution
/// header renderer is connected (step 2 of the objc-evolution-interface
/// proposal, which removes it).
struct ObjCAnnotatedHeaderRendererUnavailableError: Error, LocalizedError {
    var errorDescription: String? {
        "The annotated Objective-C header needs MachOObjCSection's evolution renderer, which this build does not include yet."
    }
}

/// Why ``ObjCAPIEvolutionRequest/AvailabilityAttributes/inferredPlatform``
/// found no one platform to spell the availability macros for. Naming the
/// platform with ``ObjCAPIEvolutionRequest/AvailabilityAttributes/platform(_:)``
/// avoids both.
public enum ObjCAvailabilityPlatformInferenceError: Error, LocalizedError, Sendable, Equatable {
    /// The binary at `path` has no `LC_BUILD_VERSION`, or names a platform
    /// the availability macros have no name for, such as bridgeOS.
    case noPlatform(path: String)
    /// The inputs name different platforms, spelled the availability macros'
    /// way and sorted.
    case conflictingPlatforms([String])

    public var errorDescription: String? {
        switch self {
        case .noPlatform(let path):
            "No availability platform can be inferred from '\(path)': it has no LC_BUILD_VERSION, or names a platform the availability macros have no name for."
        case .conflictingPlatforms(let platforms):
            "The inputs name different availability platforms (\(platforms.joined(separator: ", ")))."
        }
    }
}

extension ObjCAPIEvolutionRequest.AvailabilityAttributes {
    /// The platform the availability macros are spelled for, `nil` for none.
    /// `paths[index]` names `machOFiles[index]` in an error.
    func platform(forInputsAt paths: [String], loadedAs machOFiles: [MachOFile]) throws -> String? {
        switch self {
        case .none:
            return nil
        case .platform(let platform):
            return platform
        case .inferredPlatform:
            var platforms: Set<String> = []
            for (path, machOFile) in zip(paths, machOFiles) {
                guard let buildPlatform = machOFile.loadCommands.buildVersionCommand?.platform,
                      let platform = Self.availabilityMacroSpelling(of: buildPlatform) else {
                    throw ObjCAvailabilityPlatformInferenceError.noPlatform(path: path)
                }
                platforms.insert(platform)
            }
            if platforms.count > 1 {
                throw ObjCAvailabilityPlatformInferenceError.conflictingPlatforms(platforms.sorted())
            }
            // No inputs at all is left to the renderer, which needs two.
            return platforms.first
        }
    }

    /// How the availability macros (`API_AVAILABLE(macos(13.0))`) spell a
    /// Mach-O build platform, `nil` for one they have no name for (bridgeOS,
    /// firmware, …). A simulator shares its device's availability domain.
    static func availabilityMacroSpelling(of buildPlatform: MachOKit.Platform) -> String? {
        switch buildPlatform {
        case .macOS:
            "macos"
        case .iOS, .iOSSimulator:
            "ios"
        case .tvOS, .tvOSSimulator:
            "tvos"
        case .watchOS, .watchOSSimulator:
            "watchos"
        case .visionOS, .visionOSSimulator:
            "visionos"
        case .macCatalyst:
            "macCatalyst"
        case .driverKit:
            "driverkit"
        default:
            nil
        }
    }
}

public struct ObjCAPIEvolutionOutcome: Sendable {
    public var evolution: ObjCAPIEvolution

    public init(evolution: ObjCAPIEvolution) {
        self.evolution = evolution
    }

    public var hasBreakingChange: Bool {
        evolution.hasBreakingChange
    }
}

/// The ObjC counterpart of `ABISnapshotLoading`.
enum ObjCAPISnapshotLoading {
    /// Loads `source` as a snapshot document. `label` overrides the
    /// document's provenance label either way.
    static func loadDocument(
        from source: SnapshotSource,
        binaryLoading: BinaryLoadingOptions,
        label: String?,
        output: some SwiftSectionOutput,
        environment: SwiftSectionEnvironment
    ) async throws -> ObjCAPISnapshotDocument {
        if try source.isSnapshotDocument() {
            output.reportProgress("Reading snapshot \(source.path)…")
            var document = try ObjCAPISnapshotDocument.decode(from: Data(contentsOf: URL(fileURLWithPath: source.path)))
            if let label {
                var provenance = document.provenance ?? ObjCAPIProvenance()
                provenance.label = label
                document.provenance = provenance
            }
            return document
        }

        output.reportProgress("Indexing \(source.path)…")
        let machOFile = try binaryLoading.machOSource(forBinaryAt: source.path).load()
        let indexer = ObjCInterfaceIndexer(machO: machOFile, imagePath: machOFile.imagePath, suppliedClasses: ObjCSuppliedClass.swiftClassesWithoutClassObjects(in: machOFile))
        try await indexer.prepare()
        let snapshotBuilder = ObjCAPISnapshotBuilder(indexer: indexer)
        let provenance = ObjCAPIProvenance(
            label: label,
            binaryPath: source.path + binaryLoading.provenancePathSuffix,
            generatorVersion: environment.generator.version,
            createdAt: environment.currentDate()
        )
        return ObjCAPISnapshotDocument(provenance: provenance, snapshot: snapshotBuilder.snapshot())
    }
}
