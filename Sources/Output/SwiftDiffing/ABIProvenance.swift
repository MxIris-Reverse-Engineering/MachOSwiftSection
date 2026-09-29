import Foundation

/// Where a snapshot (or one side of a diff) came from — carried on
/// `ABISnapshotDocument` for persisted baselines and stamped onto `ABIDiff` /
/// `ABIEvolution` so reports can name the binaries they describe.
///
/// Every field is optional: provenance is descriptive metadata, never part of
/// the ABI comparison itself (two snapshots with different provenance but equal
/// `ABISnapshot`s diff as identical).
public struct ABIProvenance: Sendable, Codable, Equatable {
    /// A human-readable version label (e.g. `"17.0"`), used as the version-axis
    /// name in evolution reports.
    public var label: String?
    /// The path of the source binary. For a dyld-shared-cache extraction this
    /// is the cache path plus the image name.
    public var binaryPath: String?
    /// The `swift-section` (or host tool) version that produced the snapshot.
    public var generatorVersion: String?
    public var createdAt: Date?

    public init(
        label: String? = nil,
        binaryPath: String? = nil,
        generatorVersion: String? = nil,
        createdAt: Date? = nil
    ) {
        self.label = label
        self.binaryPath = binaryPath
        self.generatorVersion = generatorVersion
        self.createdAt = createdAt
    }
}
