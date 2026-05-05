import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `StructMetadataProtocol`.
///
/// The protocol's methods (`structDescriptor(...)`, `fieldOffsets(...)`)
/// require a live `StructMetadata` instance. Materializing one needs a
/// loaded MachOImage; consequently, the cross-reader assertions are
/// asymmetric (the metadata originates from MachOImage but its methods
/// accept the file/image/inProcess context families).
@Suite
final class StructMetadataProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "StructMetadataProtocol"
    static var registeredTestMethodNames: Set<String> {
        StructMetadataProtocolBaseline.registeredTestMethodNames
    }

    private func loadStructTestMetadata() throws -> StructMetadata {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let wrapper = try response.value.resolve(in: machOImage)
        return try required(wrapper.struct)
    }

    /// `structDescriptor(in:)` / `structDescriptor()` — the descriptor
    /// recovered from the metadata must match the one we picked from the
    /// MachOImage's type list (same descriptor offset).
    @Test func structDescriptor() async throws {
        let pickedDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let metadata = try loadStructTestMetadata()

        let imageDescriptor = try metadata.structDescriptor(in: machOImage)
        let imageCtxDescriptor = try metadata.structDescriptor(in: imageContext)
        let inProcessDescriptor = try metadata.structDescriptor()

        // The two MachO-backed paths agree on the descriptor offset.
        #expect(imageDescriptor.offset == pickedDescriptor.offset)
        #expect(imageCtxDescriptor.offset == pickedDescriptor.offset)
        // The InProcess path returns the same descriptor by name.
        #expect(try inProcessDescriptor.name() == "StructTest")
    }

    /// `fieldOffsets(for:in:)` / `fieldOffsets(for:)` — for a concrete
    /// struct with no stored fields (`Structs.StructTest`), this returns
    /// the empty array. We verify cross-reader equality on the returned
    /// `[UInt32]`.
    @Test func fieldOffsets() async throws {
        let metadata = try loadStructTestMetadata()

        let imageOffsets = try metadata.fieldOffsets(in: machOImage)
        let imageCtxOffsets = try metadata.fieldOffsets(in: imageContext)
        let inProcessOffsets = try metadata.fieldOffsets()

        #expect(imageOffsets == imageCtxOffsets)
        #expect(imageOffsets == inProcessOffsets)
        // `Structs.StructTest` has no stored fields (only a computed `body`).
        #expect(imageOffsets.isEmpty)
    }
}
