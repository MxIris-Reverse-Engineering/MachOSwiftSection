import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `FinalClassMetadataProtocol`.
///
/// The protocol provides `descriptor(in:)` (and friends) plus
/// `fieldOffsets(for:in:)` over a `FinalClassMetadataLayout`. We
/// exercise both via `ClassMetadataObjCInterop` (which conforms via
/// the same Layout protocol) loaded from the MachOImage accessor.
///
/// **Reader asymmetry:** the metadata source originates from MachOImage;
/// the protocol methods accept any `ReadingContext` so we exercise the
/// MachO + ReadingContext overloads here.
@Suite
final class FinalClassMetadataProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "FinalClassMetadataProtocol"
    static var registeredTestMethodNames: Set<String> {
        FinalClassMetadataProtocolBaseline.registeredTestMethodNames
    }

    private func loadInteropMetadata() throws -> ClassMetadataObjCInterop {
        let descriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let wrapper = try response.value.resolve(in: machOImage)
        return try required(wrapper.class)
    }

    /// `descriptor(in:)` returns the `ClassDescriptor` referenced by the
    /// metadata's `descriptor` pointer. The result must match the picker
    /// across reader paths.
    @Test func descriptor() async throws {
        let pickedDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let metadata = try loadInteropMetadata()

        let imageDescriptor = try metadata.descriptor(in: machOImage)
        let imageCtxDescriptor = try metadata.descriptor(in: imageContext)

        #expect(imageDescriptor?.offset == pickedDescriptor.offset)
        #expect(imageCtxDescriptor?.offset == pickedDescriptor.offset)
    }

    /// `fieldOffsets(for:in:)` returns the per-field byte-offsets vector
    /// for stored properties. `Classes.ClassTest` declares only computed
    /// vars (no stored properties), so the array is empty.
    @Test func fieldOffsets() async throws {
        let metadata = try loadInteropMetadata()

        let imageOffsets: [StoredPointer] = try metadata.fieldOffsets(in: machOImage)
        let imageCtxOffsets: [StoredPointer] = try metadata.fieldOffsets(in: imageContext)

        #expect(imageOffsets == imageCtxOffsets)
        // ClassTest has no stored properties.
        #expect(imageOffsets.isEmpty)
    }
}
