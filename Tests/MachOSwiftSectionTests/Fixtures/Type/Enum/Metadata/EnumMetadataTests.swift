import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `EnumMetadata`.
///
/// Materializing an `EnumMetadata` requires invoking the metadata accessor
/// function on a *loaded* MachOImage. As a consequence, the reader
/// coverage here is asymmetric: the metadata instance only originates from
/// `MachOImage`, but methods on it accept any `MachOContext` /
/// `InProcessContext`, so the layout's descriptor is read through both the
/// image context and the in-process context.
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
        let accessor = try required(try descriptor.metadataAccessorFunction(in: imageContext))
        let response = try accessor(request: .init())
        let wrapper = try response.value.resolve(in: imageContext)
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
        let pickedDescriptor = try BaselineFixturePicker.enum_NoPayloadEnumTest(in: machOImage)
        let metadata = try loadNoPayloadEnumMetadata()
        // The descriptor reachable via `descriptor(in:)` should be the same
        // ValueTypeDescriptorWrapper kind across the imageContext and
        // inProcessContext paths.
        let imageDescriptor = try metadata.descriptor(in: imageContext)
        let inProcessDescriptor = try metadata.descriptor(in: inProcessContext)

        // ValueTypeDescriptorWrapper isn't Equatable, so compare via the
        // concrete `enum` payload's offset: through the image context it is
        // the descriptor we picked from the MachOImage's type list.
        let imageEnumOffset = try required(imageDescriptor.enum).offset
        #expect(imageEnumOffset == pickedDescriptor.offset)
        // InProcess offset is a pointer bit pattern — it must be non-zero.
        let inProcessEnumOffset = try required(inProcessDescriptor.enum).offset
        #expect(inProcessEnumOffset != 0)

        // Kind field is a stable scalar — assert it matches the runtime
        // metadata-kind for enums.
        #expect(metadata.kind == .enum)
    }
}
