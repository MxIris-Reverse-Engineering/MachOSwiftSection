import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `EnumMetadata`.
///
/// Materializing an `EnumMetadata` requires invoking the metadata accessor
/// function on a *loaded* MachOImage. As a consequence, the cross-reader
/// equality block here is asymmetric: the metadata instance only originates
/// from `MachOImage`, but methods on it accept any `MachOContext` /
/// `InProcessContext` so we still validate the readers agree on the layout
/// values.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class EnumMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "EnumMetadata"
    static var registeredTestMethodNames: Set<String> {
        EnumMetadataBaseline.registeredTestMethodNames
    }

    /// Materialize an `EnumMetadata` for `Enums.NoPayloadEnumTest` by
    /// calling the MachOImage metadata accessor and resolving the
    /// response's value-type wrapper.
    private func loadNoPayloadEnumMetadata() throws -> EnumMetadata {
        let descriptor = try BaselineFixturePicker.enum_NoPayloadEnumTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let wrapper = try response.value.resolve(in: machOImage)
        return try required(wrapper.enum)
    }

    @Test func offset() async throws {
        let metadata = try loadNoPayloadEnumMetadata()
        // The metadata's `offset` is the file/image-relative position of
        // the metadata record. It should be a small positive value within
        // the MachO mapping, NOT a raw runtime pointer.
        #expect(metadata.offset > 0, "metadata offset should be set after accessor invocation")
        #expect(metadata.offset < Int(bitPattern: machOImage.ptr), "metadata offset should be a relative offset, not an absolute pointer")
    }

    @Test func layout() async throws {
        let metadata = try loadNoPayloadEnumMetadata()
        // Cross-reader equality on the descriptor pointer and kind. The
        // descriptor reachable via `descriptor(in:)` should be the same
        // ValueTypeDescriptorWrapper kind across MachOImage/imageContext/
        // inProcess paths.
        let imageDescriptor = try metadata.descriptor(in: machOImage)
        let imageCtxDescriptor = try metadata.descriptor(in: imageContext)
        let inProcessDescriptor = try metadata.descriptor()

        // ValueTypeDescriptorWrapper isn't Equatable, so compare via the
        // concrete `enum` payload's offset.
        let imageEnumOffset = try required(imageDescriptor.enum).offset
        let imageCtxEnumOffset = try required(imageCtxDescriptor.enum).offset
        #expect(imageEnumOffset == imageCtxEnumOffset)
        // InProcess offset is a pointer bit pattern — it must be non-zero.
        let inProcessEnumOffset = try required(inProcessDescriptor.enum).offset
        #expect(inProcessEnumOffset != 0)

        // Kind field is a stable scalar — assert it matches the runtime
        // metadata-kind for enums.
        #expect(metadata.kind == .enum)
    }
}
