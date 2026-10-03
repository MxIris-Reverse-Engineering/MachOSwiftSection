import Foundation
import MachOKit
import MachOFoundation
import SwiftDiffing
import SwiftIndexing
import SwiftInterface

/// The input plumbing `snapshot`, `diff` and `evolution` share: a source is
/// either a persisted document, decoded, or a binary, indexed and frozen with
/// its provenance stamped. One implementation, so the three cannot drift in
/// how they sniff, load, index or stamp.
enum ABISnapshotLoading {
    /// Loads `source` as a snapshot document.
    ///
    /// `label` overrides the document's provenance label either way.
    /// `indexingLabel` names the input to its indexing-event handlers —
    /// inputs index concurrently, so an unlabeled line could not be
    /// attributed — and defaults to `label`, then to the input's file name.
    static func loadDocument(
        from source: SnapshotSource,
        binaryLoading: BinaryLoadingOptions,
        label: String?,
        indexingLabel: String? = nil,
        output: some SwiftSectionOutput,
        environment: SwiftSectionEnvironment
    ) async throws -> ABISnapshotDocument {
        if try source.isSnapshotDocument() {
            output.reportProgress("Reading snapshot \(source.path)…")
            var document = try ABISnapshotDocument.decode(from: Data(contentsOf: URL(fileURLWithPath: source.path)))
            if let label {
                var provenance = document.provenance ?? ABIProvenance()
                provenance.label = label
                document.provenance = provenance
            }
            return document
        }

        output.reportProgress("Indexing \(source.path)…")
        let machOFile = try binaryLoading.machOSource(forBinaryAt: source.path).load()
        let builder = SwiftDiffableInterfaceBuilder(
            eventHandlers: output.indexEventHandlers(forInputLabeled: indexingLabel ?? label ?? source.defaultLabel),
            in: machOFile
        )
        try await builder.prepare()
        let provenance = ABIProvenance(
            label: label,
            binaryPath: source.path + binaryLoading.provenancePathSuffix,
            generatorVersion: environment.generator.version,
            createdAt: environment.currentDate()
        )
        return ABISnapshotDocument(provenance: provenance, snapshot: builder.snapshot())
    }

    /// One label per input, or none at all.
    static func validateLabels(_ labels: [String]?, inputCount: Int) throws {
        if let labels, labels.count != inputCount {
            throw ABIEvolutionError.labelCountMismatch(labelCount: labels.count, versionCount: inputCount)
        }
    }
}
