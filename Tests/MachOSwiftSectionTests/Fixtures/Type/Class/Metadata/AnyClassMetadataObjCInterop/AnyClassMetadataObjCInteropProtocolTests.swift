import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `AnyClassMetadataObjCInteropProtocol`.
///
/// The protocol declares overload pairs (`asFinalClassMetadata`,
/// `superclass`) plus two derived booleans (`isPureObjC`,
/// `isTypeMetadata`). We exercise them against the loaded
/// `ClassMetadataObjCInterop` for `Classes.ClassTest`.
///
/// **Reader asymmetry:** the source metadata originates from MachOImage.
@Suite
final class AnyClassMetadataObjCInteropProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "AnyClassMetadataObjCInteropProtocol"
    static var registeredTestMethodNames: Set<String> {
        AnyClassMetadataObjCInteropProtocolBaseline.registeredTestMethodNames
    }

    private func loadInteropMetadata() throws -> ClassMetadataObjCInterop {
        let descriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let wrapper = try response.value.resolve(in: machOImage)
        return try required(wrapper.class)
    }

    /// `asFinalClassMetadata(in:)` re-resolves at the same offset as a
    /// `ClassMetadataObjCInterop`. Verify the offset round-trips.
    @Test func asFinalClassMetadata() async throws {
        let interop = try loadInteropMetadata()

        let imageView: ClassMetadataObjCInterop = try interop.asFinalClassMetadata(in: machOImage)
        let imageCtxView: ClassMetadataObjCInterop = try interop.asFinalClassMetadata(in: imageContext)

        #expect(imageView.offset == interop.offset)
        #expect(imageCtxView.offset == interop.offset)
    }

    /// `superclass(in:)` returns the metaclass / superclass slim view.
    /// For a Swift class with an implicit Swift root, this is non-nil.
    @Test func superclass() async throws {
        let interop = try loadInteropMetadata()
        let imageSuper = try interop.superclass(in: machOImage)
        let imageCtxSuper = try interop.superclass(in: imageContext)

        #expect(imageSuper != nil)
        #expect(imageCtxSuper != nil)
        // The two readers should agree on the superclass offset.
        #expect(imageSuper?.offset == imageCtxSuper?.offset)
    }

    /// `isPureObjC` is true when `data & 2 == 0` (i.e. NOT a Swift type).
    /// `Classes.ClassTest` is a pure Swift class, so `isPureObjC` is false.
    @Test func isPureObjC() async throws {
        let interop = try loadInteropMetadata()
        #expect(interop.isPureObjC == false)
    }

    /// `isTypeMetadata` is the inverse of `isPureObjC`.
    @Test func isTypeMetadata() async throws {
        let interop = try loadInteropMetadata()
        #expect(interop.isTypeMetadata == true)
    }
}
