import Foundation
import MachOKit
import MachOFoundation
import SwiftDiffing
import SwiftIndexing
import SwiftInterface
import Utilities

/// `swift-section diff`: compare the Swift ABI of two binaries, or of a binary
/// and a persisted baseline.
public struct ABIDiffRequest: Sendable, Equatable {
    public enum Report: Sendable, Hashable {
        /// The change list followed by the verdict line.
        case changeList
        /// The verdict line alone. It goes to the output even when the
        /// destination is a file, as it always has on the command line.
        case summary
        /// The diff with provenance, as JSON.
        case json
        /// The full interface annotated with diff markers. Both sides must be
        /// binaries: a snapshot document carries no renderable interface. With
        /// `includesBreakingChangeVerdict`, the outcome also says whether the
        /// diff breaks the ABI, at the cost of a change-list diff on top.
        case annotatedInterface(format: AnnotatedDiffFormat, includesBreakingChangeVerdict: Bool)
    }

    public var old: SnapshotSource
    public var new: SnapshotSource
    public var binaryLoading: BinaryLoadingOptions
    public var report: Report
    public var destination: ProductDestination
    /// How many inputs index at once: `nil` is the processor count, and `1`
    /// indexes the old side before the new one. Values below 1 count as 1.
    public var maximumConcurrentPreparations: Int?

    public init(
        old: SnapshotSource,
        new: SnapshotSource,
        binaryLoading: BinaryLoadingOptions = .init(),
        report: Report = .changeList,
        destination: ProductDestination = .output,
        maximumConcurrentPreparations: Int? = nil
    ) {
        self.old = old
        self.new = new
        self.binaryLoading = binaryLoading
        self.report = report
        self.destination = destination
        self.maximumConcurrentPreparations = maximumConcurrentPreparations
    }

    public func run(output: some SwiftSectionOutput, environment: SwiftSectionEnvironment) async throws -> ABIDiffOutcome {
        let concurrencyWindow = maximumConcurrentPreparations ?? ProcessInfo.processInfo.activeProcessorCount
        switch report {
        case .annotatedInterface(let format, let includesBreakingChangeVerdict):
            return try await runAnnotatedInterface(
                format: format,
                includesBreakingChangeVerdict: includesBreakingChangeVerdict,
                concurrencyWindow: concurrencyWindow,
                output: output
            )
        case .changeList, .summary, .json:
            return try await runChangeList(concurrencyWindow: concurrencyWindow, output: output, environment: environment)
        }
    }

    private func runAnnotatedInterface(
        format: AnnotatedDiffFormat,
        includesBreakingChangeVerdict: Bool,
        concurrencyWindow: Int,
        output: some SwiftSectionOutput
    ) async throws -> ABIDiffOutcome {
        try SnapshotSource.requireBinaries([old, new])

        let oldMachOFile = try binaryLoading.machOSource(forBinaryAt: old.path).load()
        let newMachOFile = try binaryLoading.machOSource(forBinaryAt: new.path).load()

        // The renderer hands each builder's dispatcher to its printers, so the
        // handlers are what puts a dropped declaration in front of the host
        // instead of on `Dispatcher`'s os_log floor.
        let oldBuilder = SwiftDiffableInterfaceBuilder(eventHandlers: output.indexEventHandlers(forInputLabeled: "old"), in: oldMachOFile)
        let newBuilder = SwiftDiffableInterfaceBuilder(eventHandlers: output.indexEventHandlers(forInputLabeled: "new"), in: newMachOFile)
        // Old side first in the window, so a window of 1 is the historical
        // order; a wider one indexes the two side by side.
        output.reportProgress(concurrencyWindow > 1 ? "Indexing old and new binaries…" : "Indexing old binary, then new binary…")
        _ = try await [oldBuilder, newBuilder].concurrentMap(maximumConcurrency: concurrencyWindow) { builder in
            try await builder.prepare()
        }

        let diff = includesBreakingChangeVerdict
            ? ABIDiffer().diff(old: oldBuilder.abiModule(), new: newBuilder.abiModule())
            : nil

        output.reportProgress("Rendering annotated interface…")
        let renderer = SwiftDiffableInterfaceRenderer(old: oldBuilder, new: newBuilder)
        let diffFormat: DiffFormat = switch format {
        case .inline:
            .inline
        case .unified:
            .unified(oldLabel: old.path, newLabel: new.path)
        case .markdownFenced:
            .markdownFenced
        }
        let annotated = await renderer.printAnnotatedInterface(format: diffFormat)

        switch destination {
        case .output:
            output.write(.annotatedInterface(annotated.string, style: .diff(isUnifiedDiff: format == .unified)))
        case .file(let path):
            try annotated.string.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            output.reportProgress("Annotated interface written to \(path)")
        }
        return ABIDiffOutcome(diff: diff)
    }

    private func runChangeList(
        concurrencyWindow: Int,
        output: some SwiftSectionOutput,
        environment: SwiftSectionEnvironment
    ) async throws -> ABIDiffOutcome {
        // Snapshot-based either way: each side is a binary, indexed and frozen
        // here, or a persisted baseline, decoded with its format version
        // validated.
        let sides: [(source: SnapshotSource, label: String)] = [(old, "old"), (new, "new")]
        let documents = try await sides.concurrentMap(maximumConcurrency: concurrencyWindow) { side in
            try await ABISnapshotLoading.loadDocument(
                from: side.source,
                binaryLoading: binaryLoading,
                label: nil,
                indexingLabel: side.label,
                output: output,
                environment: environment
            )
        }

        output.reportProgress("Diffing…")
        let diff = ABIDiffer().diff(old: documents[0], new: documents[1])

        let verdict = "ABI-breaking: \(diff.hasBreakingChange) · backward-compatible: \(diff.isBackwardCompatible)"
        switch report {
        case .json:
            let encoded = String(decoding: try ABIJSON.encoder().encode(diff), as: UTF8.self)
            try destination.deliver(encoded, to: output, announcingFileWith: { "Report written to \($0)" })
        case .summary:
            output.write(.text(verdict))
        case .changeList, .annotatedInterface:
            try destination.deliver(ABIDiffReporter().report(diff) + "\n\n" + verdict, to: output, announcingFileWith: { "Report written to \($0)" })
        }
        return ABIDiffOutcome(diff: diff)
    }
}

/// How `diff --interface` marks the lines that changed.
public enum AnnotatedDiffFormat: Sendable, Hashable {
    /// git-diff-style `+` / `-` / ` ` line prefixes.
    case inline
    /// A real unified diff (`--- old` / `+++ new` and `@@` hunks), consumable
    /// by `git apply`, `patch` or `delta`.
    case unified
    /// The inline body wrapped in a Markdown ```` ```diff ```` fence.
    case markdownFenced
}

public struct ABIDiffOutcome: Sendable {
    /// The change-list diff; `nil` only for an annotated interface requested
    /// without the verdict.
    public var diff: ABIDiff?

    public init(diff: ABIDiff?) {
        self.diff = diff
    }

    /// Whether the diff breaks the ABI; `nil` when it was not computed.
    public var hasBreakingChange: Bool? {
        diff?.hasBreakingChange
    }
}
