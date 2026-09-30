import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `MetadataProtocol`.
///
/// Per the protocol-extension attribution rule (see `BaselineGenerator.swift`),
/// the multiple `extension MetadataProtocol { ... }` blocks (and the
/// constrained `extension MetadataProtocol where HeaderType: TypeMetadataHeaderBaseProtocol { ... }`
/// blocks) attribute every member to `MetadataProtocol`. The (MachO,
/// in-process, ReadingContext) overload triples collapse to a single
/// `MethodKey` under PublicMemberScanner's name-only keying.
///
/// **Reader asymmetry:** the metadata carrier originates from MachOImage's
/// accessor; `MachOFile` cannot invoke metadata accessors. Members are
/// exercised via the carrier's imageContext / in-process paths.
@Suite
final class MetadataProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MetadataProtocol"
    static var registeredTestMethodNames: Set<String> {
        MetadataProtocolBaseline.registeredTestMethodNames
    }

    /// Materialise a `StructMetadata`-conforming carrier for
    /// `Structs.StructTest` from a MachOImage metadata accessor.
    private func loadStructTestStructMetadata() throws -> StructMetadata {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: imageContext))
        let response = try accessor(request: .init())
        return try required(try response.value.resolve(in: imageContext).struct)
    }

    /// Materialise the same carrier through `inProcessContext` (offset =
    /// runtime pointer bits) for the in-process legs. The accessor's
    /// response `value` is the runtime metadata pointer, which the
    /// in-process context reads as a raw address.
    private func loadStructTestInProcessStructMetadata() throws -> StructMetadata {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: imageContext))
        let response = try accessor(request: .init())
        return try required(try response.value.resolve(in: inProcessContext).struct)
    }

    /// `createInMachO(_:)` recovers the (MachOImage, metadata) pair from a
    /// runtime metatype. The fixture's `SymbolTestsCore` types aren't
    /// statically linked into this test target, so we use the in-process
    /// `Int` (a built-in struct) as a witness — the call must return a
    /// non-nil pair whose metadata's `kind` decodes correctly.
    @Test func createInMachO() async throws {
        let result = try StructMetadata.createInMachO(Int.self)
        let pair = try required(result)
        #expect(pair.metadata.kind == .struct)
    }

    /// `createInProcess(_:)` recovers a metadata from a runtime metatype
    /// using in-process pointer dereferences. `Int` is the simplest stable
    /// witness available across all platforms.
    @Test func createInProcess() async throws {
        let metadata = try Metadata.createInProcess(Int.self)
        #expect(metadata.kind == .struct)
    }

    /// `asMetadataWrapper()` dispatches the carrier into the kind-specific
    /// `MetadataWrapper` enum and projects the matching arm.
    @Test func asMetadataWrapper() async throws {
        let carrier = try loadStructTestStructMetadata()
        let imageWrapper = try carrier.asMetadataWrapper(in: imageContext)
        #expect(imageWrapper.isStruct)
    }

    /// `asMetadata()` re-reads the kind-erased one-pointer prefix at the
    /// carrier's offset. The recovered `kind` must match.
    @Test func asMetadata() async throws {
        let carrier = try loadStructTestStructMetadata()
        let imageMetadata = try carrier.asMetadata(in: imageContext)
        #expect(imageMetadata.kind == .struct)
    }

    /// `kind` projects the carrier's metadata kind from the `layout.kind`
    /// scalar. Reader-independent (the layout value is read at materialise
    /// time and stored in the carrier).
    @Test func kind() async throws {
        let carrier = try loadStructTestStructMetadata()
        #expect(carrier.kind == .struct)
    }

    /// `asMetatype()` recovers the original `Any.Type`. Round-trip through
    /// `Int` since the SymbolTestsCore types aren't statically linked.
    @Test func asMetatype() async throws {
        // Use a `Metadata` constructed from `Int.self` so the metatype
        // recovery is self-contained (no fixture import required).
        let metadata = try Metadata.createInProcess(Int.self)
        let recovered: Int.Type = try metadata.asMetatype()
        #expect(recovered == Int.self)
    }

    /// `asFullMetadata()` returns the (header + metadata) pair preceded
    /// by the metadata pointer. The metadata sub-layout's `kind` must
    /// decode to `.struct` for our value-type carrier.
    @Test func asFullMetadata() async throws {
        let carrier = try loadStructTestStructMetadata()
        let imageFullMetadata = try carrier.asFullMetadata(in: imageContext)
        #expect(imageFullMetadata.layout.metadata.kind == StoredPointer(MetadataKind.struct.rawValue))
    }

    /// `valueWitnesses()` resolves the witness table through the
    /// full-metadata header. The same carrier read through the in-process
    /// context must resolve a table whose type layout agrees with the
    /// image-context one.
    @Test func valueWitnesses() async throws {
        let imageValueWitnesses = try loadStructTestStructMetadata().valueWitnesses(in: imageContext)
        let inProcessValueWitnesses = try loadStructTestInProcessStructMetadata().valueWitnesses(in: inProcessContext)
        #expect(inProcessValueWitnesses.typeLayout.size == imageValueWitnesses.typeLayout.size)
        #expect(inProcessValueWitnesses.typeLayout.stride == imageValueWitnesses.typeLayout.stride)
        #expect(inProcessValueWitnesses.typeLayout.flags == imageValueWitnesses.typeLayout.flags)
    }

    /// `isAnyExistentialType` is `false` for the struct carrier.
    @Test func isAnyExistentialType() async throws {
        let carrier = try loadStructTestStructMetadata()
        #expect(carrier.isAnyExistentialType == false)
    }

    /// `typeLayout()` resolves the type layout from the value-witnesses
    /// table; the in-process reading of the same carrier must agree with
    /// the image-context one on every field.
    @Test func typeLayout() async throws {
        let imageTypeLayout = try loadStructTestStructMetadata().typeLayout(in: imageContext)
        let inProcessTypeLayout = try loadStructTestInProcessStructMetadata().typeLayout(in: inProcessContext)
        #expect(inProcessTypeLayout.size == imageTypeLayout.size)
        #expect(inProcessTypeLayout.stride == imageTypeLayout.stride)
        #expect(inProcessTypeLayout.flags == imageTypeLayout.flags)
        #expect(inProcessTypeLayout.extraInhabitantCount == imageTypeLayout.extraInhabitantCount)
    }

    /// `typeContextDescriptorWrapper()` recovers the descriptor wrapper
    /// for the carrier; for our `StructTest` this is the `.struct` arm,
    /// holding the descriptor we picked from the MachOImage's type list.
    @Test func typeContextDescriptorWrapper() async throws {
        let pickedDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let carrier = try loadStructTestStructMetadata()
        let imageWrapper = try required(try carrier.typeContextDescriptorWrapper(in: imageContext))
        let imageStructDescriptor = try required(imageWrapper.struct)
        #expect(imageStructDescriptor.offset == pickedDescriptor.offset)
    }
}
