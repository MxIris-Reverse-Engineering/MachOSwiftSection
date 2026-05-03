import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `TypeMetadataHeader`.
///
/// `TypeMetadataHeader` is the (`layoutString`, `valueWitnesses`) prefix
/// preceding value-type metadata records. It is reachable through
/// `MetadataProtocol.asFullMetadata` for any value-type metadata.
///
/// **Reader asymmetry:** the metadata source originates from MachOImage's
/// metadata accessor; `MachOFile` cannot invoke runtime functions.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class TypeMetadataHeaderTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "TypeMetadataHeader"
    static var registeredTestMethodNames: Set<String> {
        TypeMetadataHeaderBaseline.registeredTestMethodNames
    }

    /// Materialise a `TypeMetadataHeader` for `Structs.StructTest` from
    /// the loaded MachOImage's metadata accessor via the full-metadata
    /// header projection.
    private func loadStructTestTypeHeader() throws -> TypeMetadataHeader {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let structMetadata = try required(try response.value.resolve(in: machOImage).struct)
        let fullMetadata = try structMetadata.asFullMetadata(in: machOImage)
        // Header lives at structMetadata.offset - layoutSize.
        return try machOImage.readWrapperElement(offset: fullMetadata.offset)
    }

    @Test func offset() async throws {
        let header = try loadStructTestTypeHeader()
        #expect(header.offset >= 0)
    }

    @Test func layout() async throws {
        let header = try loadStructTestTypeHeader()
        // The valueWitnesses pointer must be non-nil for any value-type
        // metadata.
        #expect(header.layout.valueWitnesses.address != 0)
    }
}
