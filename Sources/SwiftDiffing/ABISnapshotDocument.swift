import Foundation

/// The versioned persistence envelope around an `ABISnapshot` — the on-disk
/// baseline format.
///
/// `ABISnapshot` itself stays pure ABI data (its `Equatable` means "same
/// ABI"); this wrapper adds what persistence needs: a **format version** and
/// optional **provenance**. The member key strings (`"field:"`, `"tag:N|"`,
/// `"|acc:"`, `"extbucket:"`, …) are the de-facto serialization format, so any
/// key-scheme change MUST bump ``currentFormatVersion`` — decoding then fails
/// with a typed, user-facing error instead of silently mis-diffing an old
/// baseline.
public struct ABISnapshotDocument: Sendable, Codable, Equatable {
    /// Bump on any change to the snapshot schema **or** to the `MemberRecord` /
    /// extension-bucket key scheme (see `MemberRecord` and
    /// `ABIDiffer.extensionBucketKey(for:)`).
    ///
    /// History:
    /// - 2: enum-case payload keys fold in the `indirect` flag
    ///   (`tag:N|indirect|…`), so a version-1 baseline would silently miss
    ///   that transition.
    /// - 1: initial versioned format.
    public static let currentFormatVersion = 2

    public let formatVersion: Int
    public var provenance: ABIProvenance?
    public var snapshot: ABISnapshot

    public init(provenance: ABIProvenance? = nil, snapshot: ABISnapshot) {
        self.formatVersion = Self.currentFormatVersion
        self.provenance = provenance
        self.snapshot = snapshot
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) else {
            throw ABISnapshotDocumentError.missingFormatVersion
        }
        guard formatVersion == Self.currentFormatVersion else {
            throw ABISnapshotDocumentError.unsupportedFormatVersion(
                found: formatVersion,
                supported: Self.currentFormatVersion
            )
        }
        self.formatVersion = formatVersion
        self.provenance = try container.decodeIfPresent(ABIProvenance.self, forKey: .provenance)
        self.snapshot = try container.decode(ABISnapshot.self, forKey: .snapshot)
    }
}

extension ABISnapshotDocument {
    /// Decode a persisted baseline, validating the format version first so a
    /// stale or foreign file fails with a clear, typed error.
    public static func decode(from data: Data) throws -> ABISnapshotDocument {
        try ABIJSON.decoder().decode(ABISnapshotDocument.self, from: data)
    }

    /// Encode for persistence. Sorted keys + pretty printing make the encoding
    /// byte-stable for identical documents, so baselines diff cleanly in git.
    public func encoded() throws -> Data {
        try ABIJSON.encoder().encode(self)
    }
}

/// Decoding failures of the persisted baseline format.
public enum ABISnapshotDocumentError: Error, Equatable, CustomStringConvertible {
    /// The file has no `formatVersion` key — it is not an `ABISnapshotDocument`
    /// (or predates the versioned format).
    case missingFormatVersion
    /// The file was written by a different format version of the tool.
    case unsupportedFormatVersion(found: Int, supported: Int)

    public var description: String {
        switch self {
        case .missingFormatVersion:
            return "The file is not an ABI snapshot document (no formatVersion key)."
        case .unsupportedFormatVersion(let found, let supported):
            return "Unsupported ABI snapshot format version \(found) (this tool supports \(supported)). Regenerate the snapshot with this tool version."
        }
    }
}

/// The one JSON dialect every SwiftDiffing value speaks when persisted:
/// ISO-8601 dates, sorted keys, pretty printing. Shared by the snapshot
/// document codec and the CLI's `--json` outputs so no two call sites drift.
public enum ABIJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
