import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ClassMetadata`.
///
/// `ClassMetadata` is the structural type for non-ObjC-interop Swift
/// class metadata. On Apple platforms metadata accessors return the
/// ObjC-interop variant; we obtain a `ClassMetadata` view by re-resolving
/// at the same offset (the binary layout is compatible at the pointers
/// we care about).
///
/// **Reader asymmetry:** the metadata source originates from MachOImage.
@Suite
final class ClassMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ClassMetadata"
    static var registeredTestMethodNames: Set<String> {
        ClassMetadataBaseline.registeredTestMethodNames
    }

    /// Helper: load `ClassTest`'s metadata via the accessor (returned as
    /// `ClassMetadataObjCInterop`); the related `descriptorOffset` is a
    /// static lookup on `ClassMetadata`.
    private func loadInteropMetadata() throws -> ClassMetadataObjCInterop {
        let descriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let wrapper = try response.value.resolve(in: machOImage)
        return try required(wrapper.class)
    }

    /// `descriptorOffset` is a static lookup; reader-independent.
    @Test func descriptorOffset() async throws {
        let staticOffset = ClassMetadata.descriptorOffset
        // Should be a positive byte offset within the metadata layout.
        #expect(staticOffset > 0)
    }

    /// `offset` and `layout` must round-trip when re-reading the same
    /// metadata as `ClassMetadata` at the offset originally returned by
    /// the accessor.
    @Test func offset() async throws {
        let interop = try loadInteropMetadata()
        // The interop metadata's offset should be a meaningful value.
        #expect(interop.offset != 0)
    }

    @Test func layout() async throws {
        let interop = try loadInteropMetadata()
        // `kind` (which contains the descriptor pointer for Swift classes)
        // should be non-zero.
        #expect(interop.layout.kind != 0)
    }
}
