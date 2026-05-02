import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ValueMetadataProtocol`.
///
/// Per the protocol-extension attribution rule (see `BaselineGenerator.swift`),
/// `descriptor` is declared in `extension ValueMetadataProtocol { ... }`
/// (across body, in-process, and ReadingContext variants) and attributes
/// to the protocol. The three overloads collapse to one MethodKey.
///
/// `ValueMetadata` instances are only obtainable via a loaded MachOImage's
/// metadata accessor, so the cross-reader assertions here are asymmetric.
@Suite
final class ValueMetadataProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ValueMetadataProtocol"
    static var registeredTestMethodNames: Set<String> {
        ValueMetadataProtocolBaseline.registeredTestMethodNames
    }

    /// Materialize a concrete `ValueMetadataProtocol`-conforming instance
    /// (a `StructMetadata` for `Structs.StructTest`).
    private func loadStructTestStructMetadata() throws -> StructMetadata {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        return try required(try response.value.resolve(in: machOImage).struct)
    }

    /// `descriptor(in:)` and `descriptor()` — the descriptor recovered
    /// from the metadata's value-type-descriptor pointer must match the
    /// one we picked from the MachOImage's type list.
    @Test func descriptor() async throws {
        let metadata = try loadStructTestStructMetadata()
        let pickedDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let imageDescriptor = try metadata.descriptor(in: machOImage)
        let imageCtxDescriptor = try metadata.descriptor(in: imageContext)
        let inProcessDescriptor = try metadata.descriptor()

        // ValueTypeDescriptorWrapper isn't trivially Equatable; compare via
        // the `.struct` payload's offset. The image and image-context paths
        // share the same MachO and therefore the same offsets.
        let imageStructOffset = try required(imageDescriptor.struct).offset
        let imageCtxStructOffset = try required(imageCtxDescriptor.struct).offset
        #expect(imageStructOffset == pickedDescriptor.offset)
        #expect(imageCtxStructOffset == pickedDescriptor.offset)

        // The InProcess path returns the same descriptor; assert by name.
        let inProcessStruct = try required(inProcessDescriptor.struct)
        #expect(try inProcessStruct.name() == "StructTest")
    }
}
