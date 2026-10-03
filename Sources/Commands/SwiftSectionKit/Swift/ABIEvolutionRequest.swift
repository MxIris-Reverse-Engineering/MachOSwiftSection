import Foundation
import MachOKit
import MachOFoundation
import SwiftDiffing
import SwiftIndexing
import SwiftInterface
import Utilities

/// `swift-section evolution`: track the Swift ABI of one module across an
/// ordered series of versions.
public struct ABIEvolutionRequest: Sendable, Equatable {
    public enum Report: Sendable, Hashable {
        /// The full lineage report.
        case lineage
        /// The header and the per-transition summary.
        case summary
        /// The evolution as JSON.
        case json
        /// The union interface annotated with per-declaration lifecycle
        /// comments. Every input must be a binary.
        case annotatedInterface
    }

    /// The inputs in version order, oldest first.
    public var inputs: [SnapshotSource]
    /// One label per input for the version axis (`17.0`, `18.0`). `nil`
    /// falls back to each snapshot's stored label, then to the file name.
    public var labels: [String]?
    public var binaryLoading: BinaryLoadingOptions
    public var report: Report
    public var destination: ProductDestination
    /// How many inputs index at once: `nil` is the processor count, and `1`
    /// indexes the versions one after the other, oldest first. Each input in
    /// flight holds its indexed image in memory, which is what this trades
    /// against. Values below 1 count as 1.
    public var maximumConcurrentPreparations: Int?

    public init(
        inputs: [SnapshotSource],
        labels: [String]? = nil,
        binaryLoading: BinaryLoadingOptions = .init(),
        report: Report = .lineage,
        destination: ProductDestination = .output,
        maximumConcurrentPreparations: Int? = nil
    ) {
        self.inputs = inputs
        self.labels = labels
        self.binaryLoading = binaryLoading
        self.report = report
        self.destination = destination
        self.maximumConcurrentPreparations = maximumConcurrentPreparations
    }

    public func run(output: some SwiftSectionOutput, environment: SwiftSectionEnvironment) async throws -> ABIEvolutionOutcome {
        try ABISnapshotLoading.validateLabels(labels, inputCount: inputs.count)
        let concurrencyWindow = maximumConcurrentPreparations ?? ProcessInfo.processInfo.activeProcessorCount
        if report == .annotatedInterface {
            return try await runAnnotatedInterface(concurrencyWindow: concurrencyWindow, output: output)
        }

        let explicitLabels = labels
        let documents = try await Array(inputs.enumerated()).concurrentMap(maximumConcurrency: concurrencyWindow) { inputIndex, input in
            try await ABISnapshotLoading.loadDocument(
                from: input,
                binaryLoading: binaryLoading,
                label: explicitLabels?[inputIndex],
                output: output,
                environment: environment
            )
        }

        // A snapshot input may already carry a provenance label; a binary
        // falls back to its file name, so that the axis is always readable.
        let resolvedLabels = documents.enumerated().map { inputIndex, document in
            document.provenance?.label ?? inputs[inputIndex].defaultLabel
        }

        output.reportProgress("Tracking evolution…")
        let evolution = try ABIEvolutionBuilder().evolution(of: documents, labels: resolvedLabels)

        let reportText: String = switch report {
        case .json:
            String(decoding: try ABIJSON.encoder().encode(evolution), as: UTF8.self)
        case .summary:
            ABIEvolutionReporter().summary(evolution)
        case .lineage, .annotatedInterface:
            ABIEvolutionReporter().report(evolution)
        }
        // Unlike `diff`, the file gets the trailing newline too, so that the
        // two destinations hold the same bytes.
        try destination.deliver(
            destination == .output ? reportText : reportText + "\n",
            to: output,
            announcingFileWith: { "Report written to \($0)" }
        )
        return ABIEvolutionOutcome(evolution: evolution)
    }

    /// The union interface with lifecycle annotations, rendered from the live
    /// models of every version — which is why snapshot inputs are rejected
    /// (the same constraint as `diff`'s annotated interface).
    private func runAnnotatedInterface(concurrencyWindow: Int, output: some SwiftSectionOutput) async throws -> ABIEvolutionOutcome {
        try SnapshotSource.requireBinaries(inputs)

        var machOFiles: [MachOFile] = []
        for input in inputs {
            output.reportProgress("Loading \(input.path)…")
            machOFiles.append(try binaryLoading.machOSource(forBinaryAt: input.path).load())
        }
        let resolvedLabels = inputs.enumerated().map { inputIndex, input in
            labels?[inputIndex] ?? input.defaultLabel
        }

        // The erased builder, because the version count is a runtime value
        // here; the pack-generic `SwiftEvolutionInterfaceBuilder`'s arity is
        // fixed at compile time. Each version's handlers reach its indexer and
        // its printer alike.
        let builder = try AnySwiftEvolutionInterfaceBuilder(
            eventHandlersPerVersion: { _, label in output.indexEventHandlers(forInputLabeled: label) },
            versions: machOFiles,
            labels: resolvedLabels
        )
        output.reportProgress("Indexing \(machOFiles.count) versions (\(min(concurrencyWindow, machOFiles.count)) at a time)…")
        try await builder.prepare(maximumConcurrentPreparations: concurrencyWindow)
        output.reportProgress("Rendering annotated interface…")
        let annotated = try await builder.printAnnotatedInterface()

        switch destination {
        case .output:
            output.write(.annotatedInterface(annotated.string, style: .evolution))
        case .file(let path):
            try annotated.string.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            output.reportProgress("Annotated interface written to \(path)")
        }
        return ABIEvolutionOutcome(evolution: builder.evolution)
    }
}

public struct ABIEvolutionOutcome: Sendable {
    /// The lineage; `nil` only if an annotated interface was rendered without
    /// one.
    public var evolution: ABIEvolution?

    public init(evolution: ABIEvolution?) {
        self.evolution = evolution
    }

    /// Whether any transition breaks the ABI.
    public var hasBreakingChange: Bool {
        evolution?.hasBreakingChange ?? false
    }
}
