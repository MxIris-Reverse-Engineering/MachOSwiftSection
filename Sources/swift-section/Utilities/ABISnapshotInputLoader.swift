import Foundation
import MachOKit
import MachOFoundation
import SwiftDiffing
import SwiftInterface

/// Shared input plumbing for the ABI commands (`snapshot` / `diff` /
/// `evolution`): a path is either a persisted `ABISnapshotDocument` (JSON) or
/// a Mach-O / fat binary / dyld shared cache to index and freeze. Centralized
/// so the three commands cannot drift in how they sniff, load, index, or stamp
/// provenance.
enum ABISnapshotInputLoader {
    /// A snapshot document begins with `{` (after whitespace); every Mach-O,
    /// fat, or cache input begins with a binary magic. One byte decides.
    static func isSnapshotDocument(atPath path: String) throws -> Bool {
        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { fileHandle.closeFile() }
        let prefix = fileHandle.readData(ofLength: 64)
        let firstNonWhitespace = prefix.first { byte in
            byte != UInt8(ascii: " ") && byte != UInt8(ascii: "\n")
                && byte != UInt8(ascii: "\r") && byte != UInt8(ascii: "\t")
        }
        return firstNonWhitespace == UInt8(ascii: "{")
    }

    /// Load one input as a frozen snapshot document. A JSON path decodes (with
    /// the format-version check); a binary path is loaded, indexed, and frozen,
    /// with provenance stamped from the load parameters. `label` overrides the
    /// document's provenance label either way.
    static func loadDocument(
        path: String,
        architecture: Architecture?,
        isDyldSharedCache: Bool,
        cacheImageName: String?,
        cacheImagePath: String?,
        label: String?,
        log: (String) -> Void
    ) async throws -> ABISnapshotDocument {
        if try isSnapshotDocument(atPath: path) {
            log("Reading snapshot \(path)…")
            var document = try ABISnapshotDocument.decode(from: Data(contentsOf: URL(fileURLWithPath: path)))
            if let label {
                var provenance = document.provenance ?? ABIProvenance()
                provenance.label = label
                document.provenance = provenance
            }
            return document
        }

        log("Indexing \(path)…")
        let machOFile = try MachOFile.load(
            filePath: path,
            isDyldSharedCache: isDyldSharedCache,
            usesSystemDyldSharedCache: false,
            cacheImageName: cacheImageName,
            cacheImagePath: cacheImagePath,
            architecture: architecture
        )
        let builder = SwiftDiffableInterfaceBuilder(in: machOFile)
        try await builder.prepare()
        let cacheImageSuffix = [cacheImageName, cacheImagePath].compactMap { $0 }.first.map { " (\($0))" } ?? ""
        let provenance = ABIProvenance(
            label: label,
            binaryPath: path + cacheImageSuffix,
            generatorVersion: BundledVersion.value,
            createdAt: Date()
        )
        return ABISnapshotDocument(provenance: provenance, snapshot: builder.snapshot())
    }

    /// Split a `--labels a,b,c` value and require one label per input.
    static func parseLabels(_ commaSeparatedLabels: String?, inputCount: Int) throws -> [String?] {
        guard let commaSeparatedLabels else {
            return Array(repeating: nil, count: inputCount)
        }
        let labels = commaSeparatedLabels
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard labels.count == inputCount else {
            throw ABIEvolutionError.labelCountMismatch(labelCount: labels.count, versionCount: inputCount)
        }
        return labels
    }

    /// The fallback axis label for an input path: its file name.
    static func defaultLabel(forPath path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
