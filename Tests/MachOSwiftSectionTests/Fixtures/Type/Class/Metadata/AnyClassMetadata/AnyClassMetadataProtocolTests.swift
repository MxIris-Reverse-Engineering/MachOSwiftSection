import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `AnyClassMetadataProtocol`.
///
/// The protocol's `asFinalClassMetadata(...)` overloads (MachO + InProcess
/// + ReadingContext) require a type that conforms to
/// `AnyClassMetadataProtocol` but NOT to its more-specific descendant
/// `AnyClassMetadataObjCInteropProtocol` (the latter overrides the method
/// with a `ClassMetadataObjCInterop` return type, which is what runs for
/// `ClassMetadataObjCInterop` instances).
///
/// We therefore exercise the method against an `AnyClassMetadata` slim
/// view re-resolved at the same offset as the loaded
/// `ClassMetadataObjCInterop`.
///
/// **Reader asymmetry:** the metadata source originates from MachOImage.
@Suite
final class AnyClassMetadataProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "AnyClassMetadataProtocol"
    static var registeredTestMethodNames: Set<String> {
        AnyClassMetadataProtocolBaseline.registeredTestMethodNames
    }

    /// Helper: load `ClassMetadataObjCInterop` for `ClassTest`, then
    /// re-resolve at the same offset as a slim `AnyClassMetadata`.
    private func loadAnyClassMetadata() throws -> AnyClassMetadata {
        let descriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let wrapper = try response.value.resolve(in: machOImage)
        let interop = try required(wrapper.class)
        return try AnyClassMetadata.resolve(from: interop.offset, in: machOImage)
    }

    /// `asFinalClassMetadata(in:)` re-resolves the metadata at its own
    /// offset as an `AnyClassMetadata`. The slim view's offset must
    /// agree with the source's offset across reader paths.
    @Test func asFinalClassMetadata() async throws {
        let any = try loadAnyClassMetadata()

        let imageView: AnyClassMetadata = try any.asFinalClassMetadata(in: machOImage)
        let imageCtxView: AnyClassMetadata = try any.asFinalClassMetadata(in: imageContext)

        #expect(imageView.offset == any.offset)
        #expect(imageCtxView.offset == any.offset)
    }
}
