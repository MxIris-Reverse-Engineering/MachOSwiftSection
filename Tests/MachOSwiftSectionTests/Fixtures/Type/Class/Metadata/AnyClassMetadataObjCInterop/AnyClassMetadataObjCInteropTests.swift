import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `AnyClassMetadataObjCInterop`.
///
/// `AnyClassMetadataObjCInterop` is the parallel to `AnyClassMetadata`
/// for ObjC-interop classes (carrying the cache / vtable / data words).
/// We obtain one by chaining a `superclass(in:)` lookup on the loaded
/// `ClassMetadataObjCInterop` for `Classes.ClassTest`.
///
/// **Reader asymmetry:** the metadata source originates from MachOImage.
@Suite
final class AnyClassMetadataObjCInteropTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "AnyClassMetadataObjCInterop"
    static var registeredTestMethodNames: Set<String> {
        AnyClassMetadataObjCInteropBaseline.registeredTestMethodNames
    }

    /// Helper: load `ClassMetadataObjCInterop` for ClassTest, then take
    /// its superclass to get an `AnyClassMetadataObjCInterop` slim view.
    private func loadAnyInteropSuperclass() throws -> AnyClassMetadataObjCInterop {
        let descriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let wrapper = try response.value.resolve(in: machOImage)
        let interop = try required(wrapper.class)
        // ClassTest's superclass is the implicit Swift root `SwiftObject`,
        // which surfaces as a non-nil ObjC-interop class metadata pointer.
        return try required(try interop.superclass(in: machOImage))
    }

    @Test func offset() async throws {
        let metadata = try loadAnyInteropSuperclass()
        #expect(metadata.offset != 0)
    }

    @Test func layout() async throws {
        let metadata = try loadAnyInteropSuperclass()
        // Kind for ObjC-interop classes is the isa pointer (or its
        // metaclass on root); should always be non-zero.
        #expect(metadata.layout.kind != 0)
    }
}
