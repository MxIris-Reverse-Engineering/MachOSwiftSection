import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ValueMetadata`.
///
/// `ValueMetadata` is the kind-erased value-type metadata wrapper. Like
/// its concrete-kind cousins (`StructMetadata`/`EnumMetadata`), instances
/// are only obtainable by invoking the metadata accessor function from a
/// loaded MachOImage; the cross-reader assertions are asymmetric because
/// the metadata originates from `MachOImage`.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class ValueMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ValueMetadata"
    static var registeredTestMethodNames: Set<String> {
        ValueMetadataBaseline.registeredTestMethodNames
    }

    /// Materialize a `ValueMetadata` by reading the kind-erased layout at
    /// the offset of the metadata for `Structs.StructTest`. The struct's
    /// metadata is a `StructMetadata` whose layout shares the
    /// `kind`/`descriptor` prefix with `ValueMetadata`.
    private func loadStructTestValueMetadata() throws -> ValueMetadata {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let structMetadata = try required(try response.value.resolve(in: machOImage).struct)
        // ValueMetadata shares the (kind, descriptor) prefix with StructMetadata.
        return try machOImage.readWrapperElement(offset: structMetadata.offset)
    }

    @Test func offset() async throws {
        let metadata = try loadStructTestValueMetadata()
        // Sanity: offset should be a non-zero relative position.
        #expect(metadata.offset > 0)
    }

    @Test func layout() async throws {
        let metadata = try loadStructTestValueMetadata()
        // The descriptor pointer in the layout should resolve to the same
        // `ValueTypeDescriptorWrapper` we obtained from the picker.
        let descriptorWrapper = try metadata.layout.descriptor.resolve(in: machOImage)
        let pickerDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let resolvedStructOffset = try required(descriptorWrapper.struct).offset
        #expect(resolvedStructOffset == pickerDescriptor.offset)
    }
}
