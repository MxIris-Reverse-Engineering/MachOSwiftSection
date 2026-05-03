import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `HeapMetadataHeader`.
///
/// `HeapMetadataHeader` is the prefix preceding heap metadata records
/// (`(layoutString, destroy, valueWitnesses)` triple). It is reachable
/// through `MetadataProtocol.asFullMetadata` for any heap-class metadata.
///
/// **Reader asymmetry:** the metadata source originates from MachOImage's
/// metadata accessor; `MachOFile` cannot invoke runtime functions.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class HeapMetadataHeaderTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "HeapMetadataHeader"
    static var registeredTestMethodNames: Set<String> {
        HeapMetadataHeaderBaseline.registeredTestMethodNames
    }

    /// Materialise a `HeapMetadataHeader` for `Classes.ClassTest` from the
    /// loaded MachOImage's metadata accessor. The class metadata is loaded
    /// as `ClassMetadataObjCInterop`; the heap header lives at
    /// `interop.offset - HeapMetadataHeader.layoutSize`.
    private func loadClassTestHeapHeader() throws -> HeapMetadataHeader {
        let descriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let interop = try required(try response.value.resolve(in: machOImage).class)
        return try machOImage.readWrapperElement(offset: interop.offset - HeapMetadataHeader.layoutSize)
    }

    @Test func offset() async throws {
        let header = try loadClassTestHeapHeader()
        // The heap header offset must precede the class metadata pointer.
        #expect(header.offset > 0)
    }

    @Test func layout() async throws {
        let header = try loadClassTestHeapHeader()
        // The valueWitnesses pointer must be non-nil — every Swift heap
        // metadata carries a witness table for cleanup.
        #expect(header.layout.valueWitnesses.address != 0)
    }
}
