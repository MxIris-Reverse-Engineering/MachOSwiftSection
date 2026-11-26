import Foundation
import MachOKit
@testable import MachOSwiftSection
import ObjCMetadataSource
import ObjCIndexing
import ObjCInterface
import ObjCDiffing

/// A dump over an ordered series of versions — a diff or an evolution. A
/// conforming suite supplies the axis each pipeline runs over, usually by
/// inheriting one of the axis base classes below.
protocol VersionAxisDumpTests: InspectionDumpTests {
    func versionAxis(for language: MetadataLanguage) -> VersionAxis
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension VersionAxisDumpTests {
    /// One image indexed the way `swift-section objc snapshot` indexes it and
    /// frozen into a labeled snapshot document, round-tripped through the
    /// persisted form: what a diff or an evolution consumes is exactly what a
    /// saved baseline would decode to.
    func objcSnapshotDocument(of image: AxisImage, label: String) async throws -> ObjCAPISnapshotDocument {
        let indexer = try await preparedObjCIndexer(of: image.machOFile)
        let document = ObjCAPISnapshotDocument(
            provenance: ObjCAPIProvenance(
                label: label,
                binaryPath: image.machOFile.imagePath,
                generatorVersion: "IntegrationTests",
                createdAt: Date()
            ),
            snapshot: ObjCAPISnapshotBuilder(indexer: indexer).snapshot()
        )
        return try ObjCAPISnapshotDocument.decode(from: document.encoded())
    }
}
