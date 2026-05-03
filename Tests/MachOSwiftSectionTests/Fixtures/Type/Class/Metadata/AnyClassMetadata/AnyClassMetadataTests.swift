import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `AnyClassMetadata`.
///
/// `AnyClassMetadata` represents the slim header (kind + superclass
/// pointer) used as the structural root for pure-Swift class metadata
/// (no ObjC interop). On Apple platforms, the metadata accessor for a
/// Swift class returns `ClassMetadataObjCInterop` (the ObjC-interop
/// variant), which is what's actually loaded at runtime, NOT the
/// non-interop `AnyClassMetadata`. As such, `AnyClassMetadata` is
/// reachable via deliberate `asFinalClassMetadata(in:)` casts on
/// `AnyClassMetadataProtocol`, not from the accessor flow directly.
///
/// **Reader asymmetry:** the metadata instance only originates from
/// `MachOImage`; `MachOFile` cannot invoke metadata accessors.
///
/// We obtain an `AnyClassMetadata` by loading the
/// `ClassMetadataObjCInterop` for `Classes.ClassTest` and casting it
/// down via the protocol's `asFinalClassMetadata(in:)` helper, then
/// performing structural checks on the slim header.
@Suite
final class AnyClassMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "AnyClassMetadata"
    static var registeredTestMethodNames: Set<String> {
        AnyClassMetadataBaseline.registeredTestMethodNames
    }

    /// Helper: load the `ClassMetadataObjCInterop` for `ClassTest` and
    /// re-resolve at the same offset as an `AnyClassMetadata` slim view.
    /// The two layouts overlap in their leading fields (kind +
    /// superclass), so the slim re-resolution succeeds.
    private func loadAnyClassMetadata() throws -> AnyClassMetadata {
        let descriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let wrapper = try response.value.resolve(in: machOImage)
        let interop = try required(wrapper.class)
        return try AnyClassMetadata.resolve(from: interop.offset, in: machOImage)
    }

    @Test func offset() async throws {
        let metadata = try loadAnyClassMetadata()
        // The cast preserves the metadata's offset; we verify it's
        // non-zero (resolution succeeded).
        #expect(metadata.offset != 0)
    }

    @Test func layout() async throws {
        let metadata = try loadAnyClassMetadata()
        // Kind is the first scalar; for a Swift class this encodes a
        // descriptor pointer and should be non-zero.
        #expect(metadata.layout.kind != 0)
    }
}
