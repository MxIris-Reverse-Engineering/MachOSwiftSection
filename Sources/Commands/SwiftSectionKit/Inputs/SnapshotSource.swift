import Foundation

/// Where a snapshot comes from, for `snapshot`, `diff` and `evolution`.
public enum SnapshotSource: Sendable, Hashable {
    /// A snapshot document (JSON) or a binary to index on the spot. The file's
    /// first non-whitespace byte tells them apart: a document begins with `{`,
    /// every Mach-O, fat or cache file with a binary magic.
    case path(String)
}

public enum SnapshotSourceError: Error, LocalizedError, Sendable, Equatable {
    /// An annotated interface renders from the live models, and a snapshot
    /// document carries none; `path` names the document that was given.
    case binaryRequired(path: String)

    public var errorDescription: String? {
        switch self {
        case .binaryRequired(let path):
            "An annotated interface needs binaries; '\(path)' is a snapshot document, which carries no renderable interface."
        }
    }
}

/// How `snapshot`, `diff` and `evolution` load an input that turns out to be a
/// binary. A snapshot document input ignores it.
public struct BinaryLoadingOptions: Sendable, Hashable {
    /// The slice to pick from a fat binary.
    public var architecture: Architecture?
    /// When set, every binary input is a dyld shared cache, and this image is
    /// extracted from each — the way to diff one framework across two OS
    /// versions' caches.
    public var dyldSharedCacheImage: DyldSharedCacheImage?

    public init(architecture: Architecture? = nil, dyldSharedCacheImage: DyldSharedCacheImage? = nil) {
        self.architecture = architecture
        self.dyldSharedCacheImage = dyldSharedCacheImage
    }

    /// The Mach-O source a binary input at `path` names.
    func machOSource(forBinaryAt path: String) -> MachOSource {
        if let dyldSharedCacheImage {
            return .dyldSharedCache(cachePath: path, image: dyldSharedCacheImage)
        } else {
            return .file(path: path, architecture: architecture)
        }
    }

    /// What provenance records after the input path, so that two images of
    /// one cache stay distinguishable: " (SwiftUICore)".
    var provenancePathSuffix: String {
        switch dyldSharedCacheImage {
        case .name(let name):
            " (\(name))"
        case .path(let path):
            " (\(path))"
        case nil:
            ""
        }
    }
}

extension SnapshotSource {
    var path: String {
        switch self {
        case .path(let path):
            path
        }
    }

    /// Whether the file is a snapshot document rather than a binary. One byte
    /// decides: the first that is not whitespace.
    func isSnapshotDocument() throws -> Bool {
        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { fileHandle.closeFile() }
        let prefix = fileHandle.readData(ofLength: 64)
        let firstNonWhitespace = prefix.first { byte in
            byte != UInt8(ascii: " ") && byte != UInt8(ascii: "\n")
                && byte != UInt8(ascii: "\r") && byte != UInt8(ascii: "\t")
        }
        return firstNonWhitespace == UInt8(ascii: "{")
    }

    /// The axis label an input gets when nobody named it: its file name.
    var defaultLabel: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// Throws ``SnapshotSourceError/binaryRequired(path:)`` for the first of
    /// `sources` that is a snapshot document. Every input is checked before
    /// any is loaded, so a mistake costs no indexing.
    static func requireBinaries(_ sources: [SnapshotSource]) throws {
        for source in sources where try source.isSnapshotDocument() {
            throw SnapshotSourceError.binaryRequired(path: source.path)
        }
    }
}
