import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `EnumMetadataProtocol`.
///
/// The protocol's methods (`enumDescriptor(...)`, `payloadSize(...)`)
/// require a live `EnumMetadata` instance. Materializing one needs a
/// loaded MachOImage; consequently, the cross-reader assertions are
/// asymmetric (the metadata originates from MachOImage but its methods
/// accept the file/image/inProcess context families).
///
/// We use two pickers:
///   - `Enums.NoPayloadEnumTest` — has `payloadSizeOffset == 0` so
///     `payloadSize(...)` returns nil.
///   - `Enums.SinglePayloadEnumTest` — same: it is a single-payload enum
///     but `payloadSizeOffset` is also zero in the descriptor; the
///     baseline records this invariant. (No fixture in `SymbolTestsCore`
///     currently surfaces a non-nil `payloadSize`.)
@Suite
final class EnumMetadataProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "EnumMetadataProtocol"
    static var registeredTestMethodNames: Set<String> {
        EnumMetadataProtocolBaseline.registeredTestMethodNames
    }

    private func loadNoPayloadEnumMetadata() throws -> EnumMetadata {
        let descriptor = try BaselineFixturePicker.enum_NoPayloadEnumTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let wrapper = try response.value.resolve(in: machOImage)
        return try required(wrapper.enum)
    }

    /// `enumDescriptor(in:)` / `enumDescriptor()` — the descriptor recovered
    /// from the metadata must match the one we picked from the MachOImage's
    /// type list (same descriptor offset).
    @Test func enumDescriptor() async throws {
        let pickedDescriptor = try BaselineFixturePicker.enum_NoPayloadEnumTest(in: machOImage)
        let metadata = try loadNoPayloadEnumMetadata()

        let imageDescriptor = try metadata.enumDescriptor(in: machOImage)
        let imageCtxDescriptor = try metadata.enumDescriptor(in: imageContext)
        let inProcessDescriptor = try metadata.enumDescriptor()

        // The two MachO-backed paths agree on the descriptor offset.
        #expect(imageDescriptor.offset == pickedDescriptor.offset)
        #expect(imageCtxDescriptor.offset == pickedDescriptor.offset)
        // The InProcess path returns the same descriptor by name.
        #expect(try inProcessDescriptor.name() == "NoPayloadEnumTest")
    }

    /// `payloadSize(descriptor:in:)` / `payloadSize(descriptor:)` — for
    /// `Enums.NoPayloadEnumTest` (no payload cases, `payloadSizeOffset == 0`),
    /// this returns nil regardless of the reader.
    @Test func payloadSize() async throws {
        let metadata = try loadNoPayloadEnumMetadata()

        let imagePayload = try metadata.payloadSize(in: machOImage)
        let imageCtxPayload = try metadata.payloadSize(in: imageContext)
        let inProcessPayload = try metadata.payloadSize()

        // No payload cases ⇒ no `payloadSizeOffset` ⇒ all nil.
        #expect(imagePayload == nil)
        #expect(imageCtxPayload == nil)
        #expect(inProcessPayload == nil)
    }
}
