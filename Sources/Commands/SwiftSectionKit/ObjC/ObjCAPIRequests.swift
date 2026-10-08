import Foundation
import MachOKit
import ObjCDiffing
import ObjCIndexing
import ObjCInterface
import ObjCMetadataSource

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
        case .lineage:
            ObjCAPIEvolutionReporter().report(evolution)
        }
        try destination.deliver(
            destination == .output ? reportText : reportText + "\n",
            to: output,
            announcingFileWith: { "Report written to \($0)" }
        )
        return ObjCAPIEvolutionOutcome(evolution: evolution)
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
        let indexer = ObjCInterfaceIndexer(machO: machOFile, imagePath: machOFile.imagePath)
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
