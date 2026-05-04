import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `HeapMetadataHeaderPrefix`.
///
/// `HeapMetadataHeaderPrefix` is the single-`destroy`-pointer slot
/// embedded in every heap metadata's three-word layout prefix
/// `(layoutString, destroy, valueWitnesses)`. Phase C5 converts this
/// suite to a real test that materialises the prefix at the second word
/// of `Classes.ClassTest`'s heap metadata layout
/// (offset = `interop.offset - HeapMetadataHeader.layoutSize +
/// TypeMetadataLayoutPrefix.layoutSize`).
///
/// **Reader asymmetry:** the source class metadata pointer comes from
/// MachOImage's metadata accessor, so the helper is `acrossAllReaders`
/// in the scanner — `MachOFile` cannot invoke runtime accessor functions.
/// The Suite asserts the prefix's offset is positive and its `destroy`
/// pointer is non-nil — every Swift heap metadata carries a destroy
/// callback installed by the Swift runtime at type-load time.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class HeapMetadataHeaderPrefixTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "HeapMetadataHeaderPrefix"
    static var registeredTestMethodNames: Set<String> {
        HeapMetadataHeaderPrefixBaseline.registeredTestMethodNames
    }

    /// Materialise a `HeapMetadataHeaderPrefix` for `Classes.ClassTest` from
    /// the loaded MachOImage. The class metadata is loaded as
    /// `ClassMetadataObjCInterop`; the heap-header prefix lives at
    /// `interop.offset - HeapMetadataHeader.layoutSize +
    /// TypeMetadataLayoutPrefix.layoutSize` (i.e. one word into the
    /// three-word heap-header layout).
    private func loadClassTestHeapHeaderPrefix() throws -> HeapMetadataHeaderPrefix {
        let descriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let interop = try required(try response.value.resolve(in: machOImage).class)
        let prefixOffset = interop.offset
            - HeapMetadataHeader.layoutSize
            + TypeMetadataLayoutPrefix.layoutSize
        return try machOImage.readWrapperElement(offset: prefixOffset)
    }

    @Test func offset() async throws {
        let prefix = try loadClassTestHeapHeaderPrefix()
        // The prefix offset must precede the class metadata pointer.
        #expect(prefix.offset > 0)
    }

    @Test func layout() async throws {
        let prefix = try loadClassTestHeapHeaderPrefix()
        // Every Swift heap metadata carries a non-nil destroy pointer
        // (the runtime installs `swift_release` or a custom destroyer at
        // type-load time).
        #expect(prefix.layout.destroy.address != 0)
    }
}
