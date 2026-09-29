import Foundation
import MachOKit
import ObjCDiffing
import ObjCIndexing
import ObjCInterface

/// Shared input plumbing for the API commands (`snapshot` / `diff` /
/// `evolution`): a path is either a persisted `ObjCAPISnapshotDocument`
/// (JSON) or a Mach-O / fat binary / dyld shared cache to index and freeze.
/// Centralized so the three commands cannot drift in how they sniff, load,
/// index, or stamp provenance.
enum ObjCSnapshotInputLoader {
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

    /// Load one input as a frozen snapshot document. A JSON path decodes
    /// (with the format-version check); a binary path is loaded, indexed, and
    /// frozen, with provenance stamped from the load parameters. `label`
    /// overrides the document's provenance label either way.
    static func loadDocument(
        path: String,
        architecture: Architecture?,
        isDyldSharedCache: Bool,
        cacheImageName: String?,
        cacheImagePath: String?,
        label: String?,
        log: (String) -> Void
    ) async throws -> ObjCAPISnapshotDocument {
        if try isSnapshotDocument(atPath: path) {
            log("Reading snapshot \(path)…")
            var document = try ObjCAPISnapshotDocument.decode(from: Data(contentsOf: URL(fileURLWithPath: path)))
            if let label {
                var provenance = document.provenance ?? ObjCAPIProvenance()
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
        let indexer = ObjCInterfaceIndexer(machO: machOFile, imagePath: machOFile.imagePath)
        try await indexer.prepare()
        let snapshotBuilder = ObjCAPISnapshotBuilder(indexer: indexer)
        let cacheImageSuffix = [cacheImageName, cacheImagePath].compactMap { $0 }.first.map { " (\($0))" } ?? ""
        let provenance = ObjCAPIProvenance(
            label: label,
            binaryPath: path + cacheImageSuffix,
            generatorVersion: BundledVersion.value,
            createdAt: Date()
        )
        return ObjCAPISnapshotDocument(provenance: provenance, snapshot: snapshotBuilder.snapshot())
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
            throw ObjCAPIEvolutionError.labelCountMismatch(labelCount: labels.count, versionCount: inputCount)
        }
        return labels
    }

    /// The fallback axis label for an input path: its file name.
    static func defaultLabel(forPath path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
