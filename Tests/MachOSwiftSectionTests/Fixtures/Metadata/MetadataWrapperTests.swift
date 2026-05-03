import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `MetadataWrapper`.
///
/// `MetadataWrapper` is the `@CaseCheckable(.public)` /
/// `@AssociatedValue(.public)` enum dispatching across every metadata
/// kind. The macro-injected case-presence helpers and associated-value
/// extractors are not visited by `PublicMemberScanner`, so the source-
/// level public surface comprises only:
/// - `anyMetadata`, `metadata` (computed properties)
/// - `valueWitnessTable` (3 overloads collapsing to one MethodKey)
/// - `resolve` (3 overloads collapsing to one MethodKey)
///
/// **Reader asymmetry:** the wrapper is materialised via MachOImage's
/// metadata accessor (`StructTest.metadataAccessorFunction`); `MachOFile`
/// cannot invoke runtime functions.
@Suite
final class MetadataWrapperTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MetadataWrapper"
    static var registeredTestMethodNames: Set<String> {
        MetadataWrapperBaseline.registeredTestMethodNames
    }

    /// Materialise an image-relative wrapper for the MachOImage /
    /// imageContext code paths.
    private func loadStructTestImageWrapper() throws -> MetadataWrapper {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        return try response.value.resolve(in: machOImage)
    }

    /// Materialise an in-process wrapper (offset = runtime pointer bits)
    /// for the no-arg projection paths (`metadata`, `valueWitnessTable()`).
    /// The accessor's response `value` is the runtime metadata pointer; the
    /// no-arg `Pointer.resolve()` interprets `address` as a raw pointer.
    private func loadStructTestInProcessWrapper() throws -> MetadataWrapper {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        return try response.value.resolve()
    }

    /// `anyMetadata` projects the wrapped metadata as an existential
    /// `any MetadataProtocol`. For our `StructTest` carrier the returned
    /// existential's `kind` must be `.struct`. The projection itself is
    /// reader-independent (no MachO read; just a switch on the enum).
    @Test func anyMetadata() async throws {
        let wrapper = try loadStructTestImageWrapper()
        let metadata = wrapper.anyMetadata
        #expect(metadata.kind == .struct)
    }

    /// `metadata` re-reads the kind-erased `Metadata` prefix at the
    /// wrapped metadata's offset, interpreting the offset as a runtime
    /// raw pointer. Only the in-process wrapper produces a valid raw
    /// pointer, so we materialise the wrapper without the `in:` reader.
    @Test func metadata() async throws {
        let wrapper = try loadStructTestInProcessWrapper()
        let metadata = try wrapper.metadata
        #expect(metadata.kind == .struct)
    }

    /// `valueWitnessTable(in:)` (the MachO and ReadingContext overloads)
    /// resolves the value-witness table through the full-metadata header.
    /// Cross-reader equality on `typeLayout.size`.
    ///
    /// The no-arg `valueWitnessTable()` overload requires an in-process
    /// wrapper (offset = runtime pointer); we exercise it against the
    /// in-process variant and assert its `typeLayout.size` agrees with the
    /// image variant.
    @Test func valueWitnessTable() async throws {
        let imageWrapper = try loadStructTestImageWrapper()
        let imageVW = try imageWrapper.valueWitnessTable(in: machOImage)
        let imageCtxVW = try imageWrapper.valueWitnessTable(in: imageContext)
        #expect(imageVW.typeLayout.size == imageCtxVW.typeLayout.size)

        let inProcessWrapper = try loadStructTestInProcessWrapper()
        let inProcessVW = try inProcessWrapper.valueWitnessTable()
        #expect(inProcessVW.typeLayout.size == imageVW.typeLayout.size)
    }

    /// `resolve(...)` (3 overloads) materialises a wrapper at the given
    /// offset; the dispatch must select the same case as the original
    /// accessor invocation. We exercise the MachO-based and
    /// ReadingContext-based overloads (the `from ptr:` overload requires
    /// a runtime raw pointer and is covered by the no-arg
    /// `Pointer.resolve()` flow exercised in `metadata()`).
    @Test func resolve() async throws {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let original = try response.value.resolve(in: machOImage)
        let originalOffset = try required(original.struct).offset

        // Re-resolve at the same offset via the MachOImage path.
        let viaImage = try MetadataWrapper.resolve(from: originalOffset, in: machOImage)
        #expect(viaImage.isStruct)

        // Re-resolve via ReadingContext.
        let imageAddress = try imageContext.addressFromOffset(originalOffset)
        let viaImageContext = try MetadataWrapper.resolve(at: imageAddress, in: imageContext)
        #expect(viaImageContext.isStruct)
    }
}
