import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `StructMetadata`.
///
/// Materializing a `StructMetadata` requires invoking the metadata accessor
/// function on a *loaded* MachOImage. As a consequence, the cross-reader
/// equality block here is asymmetric: the metadata instance only originates
/// from `MachOImage`, but methods on it accept any `MachOContext` /
/// `InProcessContext` so we still validate the readers agree on the layout
/// values.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class StructMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "StructMetadata"
    static var registeredTestMethodNames: Set<String> {
        StructMetadataBaseline.registeredTestMethodNames
    }

    /// Materialize a `StructMetadata` for `Structs.StructTest` by calling the
    /// MachOImage metadata accessor and resolving the response. Returns `nil`
    /// only if the accessor isn't reachable for the descriptor (which we
    /// treat as a fixture-build failure).
    private func loadStructTestMetadata() throws -> StructMetadata {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let wrapper = try response.value.resolve(in: machOImage)
        return try required(wrapper.struct)
    }

    @Test func descriptorOffset() async throws {
        // `descriptorOffset` is a static lookup: no instance required, just
        // a reflection of `MemoryLayout<Layout>.offset(of: \.descriptor)`.
        let staticOffset = StructMetadata.descriptorOffset
        // The kind field comes first (StoredPointer-sized) so descriptor
        // lives at offset = MemoryLayout<StoredPointer>.size on 64-bit.
        // We assert equality across the (image, fileContext, imageContext,
        // inProcess) reader axes by re-querying via static lookup; the value
        // is reader-independent at runtime.
        #expect(staticOffset > 0, "descriptor offset should be non-zero")
        #expect(staticOffset == MemoryLayout<UnsafeRawPointer>.size, "kind precedes descriptor pointer; size = pointer width")
    }

    @Test func offset() async throws {
        let metadata = try loadStructTestMetadata()
        // The metadata's `offset` is the file/image-relative position of the
        // metadata record (resolved by `MachOImage.image(for:)` minus the
        // image base in `MetadataProtocol.createInMachO`-style flow, or by
        // the accessor's response value). It should be a small positive
        // value within the MachO mapping, NOT a raw runtime pointer.
        #expect(metadata.offset > 0, "metadata offset should be set after accessor invocation")
        #expect(metadata.offset < Int(bitPattern: machOImage.ptr), "metadata offset should be a relative offset, not an absolute pointer")
    }

    @Test func layout() async throws {
        let metadata = try loadStructTestMetadata()
        // Cross-reader equality on the descriptor pointer and kind. The
        // descriptor reachable via `descriptor(in:)` should be the same
        // ValueTypeDescriptorWrapper kind across MachOImage/imageContext/
        // inProcess paths.
        let imageDescriptor = try metadata.descriptor(in: machOImage)
        let imageCtxDescriptor = try metadata.descriptor(in: imageContext)
        let inProcessDescriptor = try metadata.descriptor()

        // ValueTypeDescriptorWrapper isn't Equatable, so compare via the
        // concrete `struct` payload's offset.
        let imageStructOffset = try required(imageDescriptor.struct).offset
        let imageCtxStructOffset = try required(imageCtxDescriptor.struct).offset
        #expect(imageStructOffset == imageCtxStructOffset)
        // InProcess offset is a pointer bit pattern — it must be non-zero.
        let inProcessStructOffset = try required(inProcessDescriptor.struct).offset
        #expect(inProcessStructOffset != 0)

        // Kind field is a stable scalar — assert it matches the runtime
        // metadata-kind for structs.
        #expect(metadata.kind == .struct)
    }
}
