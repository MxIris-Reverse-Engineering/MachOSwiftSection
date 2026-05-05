import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `Metadata`.
///
/// `Metadata` is the kind-erased one-pointer header shared by every
/// metadata kind. We materialize it through `Structs.StructTest`'s
/// MachOImage metadata accessor so the `kind` field decodes to a stable
/// value (`MetadataKind.struct`).
///
/// **Reader asymmetry:** the metadata source originates from MachOImage;
/// `MachOFile` cannot invoke the accessor function. The Suite still
/// asserts the structural members agree across the available reader axes.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class MetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "Metadata"
    static var registeredTestMethodNames: Set<String> {
        MetadataBaseline.registeredTestMethodNames
    }

    /// Materialize a kind-erased `Metadata` for `Structs.StructTest`.
    private func loadStructTestMetadata() throws -> Metadata {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let structMetadata = try required(try response.value.resolve(in: machOImage).struct)
        // Re-read the kind-erased prefix at the same offset.
        return try machOImage.readWrapperElement(offset: structMetadata.offset)
    }

    @Test func offset() async throws {
        let metadata = try loadStructTestMetadata()
        #expect(metadata.offset > 0)
    }

    @Test func layout() async throws {
        let metadata = try loadStructTestMetadata()
        // For value-type metadata, `kind` decodes to one of the
        // documented `MetadataKind` raw values; for `Structs.StructTest`
        // it must be `.struct` (raw 0x200). The `MetadataKind` accessor
        // (declared in `MetadataProtocol`) wraps the raw scalar.
        #expect(metadata.kind == .struct)
        #expect(metadata.layout.kind == StoredPointer(MetadataKind.struct.rawValue))
    }
}
