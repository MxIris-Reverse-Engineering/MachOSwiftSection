import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ClassMetadataObjCInterop`.
///
/// This is the live ObjC-interop variant returned by the MachOImage
/// metadata accessor for any Swift class on Apple platforms. We
/// materialise it for `Classes.ClassTest` and verify the structural
/// fields agree across reader paths.
///
/// **Reader asymmetry:** the metadata source originates from MachOImage.
@Suite
final class ClassMetadataObjCInteropTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ClassMetadataObjCInterop"
    static var registeredTestMethodNames: Set<String> {
        ClassMetadataObjCInteropBaseline.registeredTestMethodNames
    }

    private func loadInteropMetadata() throws -> ClassMetadataObjCInterop {
        let descriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let wrapper = try response.value.resolve(in: machOImage)
        return try required(wrapper.class)
    }

    @Test func descriptorOffset() async throws {
        let staticOffset = ClassMetadataObjCInterop.descriptorOffset
        #expect(staticOffset > 0)
    }

    @Test func offset() async throws {
        let metadata = try loadInteropMetadata()
        #expect(metadata.offset != 0)
    }

    @Test func layout() async throws {
        let metadata = try loadInteropMetadata()
        // The descriptor field, when resolved against the same image,
        // should return a non-nil ClassDescriptor whose offset matches
        // the picker.
        let pickedDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let resolvedDescriptor = try metadata.layout.descriptor.resolve(in: machOImage)
        #expect(resolvedDescriptor?.offset == pickedDescriptor.offset)
    }
}
