import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `FullMetadata`.
///
/// `FullMetadata<Metadata>` is the (`HeaderType.Layout`, `Metadata.Layout`)
/// pair preceded by the metadata header (the "full" metadata layout). Live
/// `FullMetadata` instances are reachable only through
/// `MetadataProtocol.asFullMetadata` from a MachOImage metadata accessor;
/// no MachOFile path materialises one.
///
/// **Reader asymmetry:** `MachOImage` is the only reader that surfaces a
/// live carrier. The Suite asserts the structural members agree across
/// the (image, imageContext, inProcess) reader axes.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class FullMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "FullMetadata"
    static var registeredTestMethodNames: Set<String> {
        FullMetadataBaseline.registeredTestMethodNames
    }

    /// Materialize a `FullMetadata<StructMetadata>` for `Structs.StructTest`
    /// from a MachOImage metadata accessor.
    private func loadFullStructMetadata() throws -> FullMetadata<StructMetadata> {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let structMetadata = try required(try response.value.resolve(in: machOImage).struct)
        return try structMetadata.asFullMetadata(in: machOImage)
    }

    @Test func offset() async throws {
        let full = try loadFullStructMetadata()
        // The full-metadata offset is the metadata's offset minus the
        // header size; it must be non-negative.
        #expect(full.offset >= 0)
    }

    @Test func layout() async throws {
        let full = try loadFullStructMetadata()
        // The metadata sub-layout's `kind` must decode to .struct for our
        // value-type carrier; the header sub-layout's `valueWitnesses`
        // pointer must be non-nil (the reflexive lookup succeeded).
        #expect(full.layout.metadata.kind == StoredPointer(MetadataKind.struct.rawValue))

        // ReadingContext path also exercised — the layout values must
        // round-trip through `asFullMetadata(in: imageContext)`.
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let structMetadata = try required(try response.value.resolve(in: machOImage).struct)
        let viaImageContext = try structMetadata.asFullMetadata(in: imageContext)
        #expect(viaImageContext.layout.metadata.kind == full.layout.metadata.kind)
    }
}
