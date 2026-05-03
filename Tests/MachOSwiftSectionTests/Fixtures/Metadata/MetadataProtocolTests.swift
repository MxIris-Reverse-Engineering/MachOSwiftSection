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
/// exercised via the carrier's MachOImage / imageContext / in-process paths.
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
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        return try required(try response.value.resolve(in: machOImage).struct)
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
        let imageWrapper = try carrier.asMetadataWrapper(in: machOImage)
        let imageCtxWrapper = try carrier.asMetadataWrapper(in: imageContext)
        #expect(imageWrapper.isStruct)
        #expect(imageCtxWrapper.isStruct)
    }

    /// `asMetadata()` re-reads the kind-erased one-pointer prefix at the
    /// carrier's offset. The recovered `kind` must match.
    @Test func asMetadata() async throws {
        let carrier = try loadStructTestStructMetadata()
        let imageMetadata = try carrier.asMetadata(in: machOImage)
        let imageCtxMetadata = try carrier.asMetadata(in: imageContext)
        #expect(imageMetadata.kind == .struct)
        #expect(imageCtxMetadata.kind == .struct)
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
    /// by the metadata pointer; the wrapped header must agree across
    /// readers.
    @Test func asFullMetadata() async throws {
        let carrier = try loadStructTestStructMetadata()
        let imageFull = try carrier.asFullMetadata(in: machOImage)
        let imageCtxFull = try carrier.asFullMetadata(in: imageContext)
        // Both readers must agree on the metadata sub-layout.
        #expect(imageFull.layout.metadata.kind == imageCtxFull.layout.metadata.kind)
    }

    /// `valueWitnesses()` resolves the witness table through the
    /// full-metadata header.
    @Test func valueWitnesses() async throws {
        let carrier = try loadStructTestStructMetadata()
        let imageVW = try carrier.valueWitnesses(in: machOImage)
        let imageCtxVW = try carrier.valueWitnesses(in: imageContext)
        // Type layouts must agree across readers (size/stride/flags).
        #expect(imageVW.typeLayout.size == imageCtxVW.typeLayout.size)
    }

    /// `isAnyExistentialType` is `false` for the struct carrier.
    @Test func isAnyExistentialType() async throws {
        let carrier = try loadStructTestStructMetadata()
        #expect(carrier.isAnyExistentialType == false)
    }

    /// `typeLayout()` resolves the type layout from the value-witnesses
    /// table; cross-reader equality on `size`.
    @Test func typeLayout() async throws {
        let carrier = try loadStructTestStructMetadata()
        let imageTL = try carrier.typeLayout(in: machOImage)
        let imageCtxTL = try carrier.typeLayout(in: imageContext)
        #expect(imageTL.size == imageCtxTL.size)
    }

    /// `typeContextDescriptorWrapper()` recovers the descriptor wrapper
    /// for the carrier; for our `StructTest` this is the `.struct` arm.
    @Test func typeContextDescriptorWrapper() async throws {
        let carrier = try loadStructTestStructMetadata()
        let imageWrapper = try required(try carrier.typeContextDescriptorWrapper(in: machOImage))
        let imageCtxWrapper = try required(try carrier.typeContextDescriptorWrapper(in: imageContext))
        // ValueTypeDescriptorWrapper isn't trivially Equatable; compare
        // via the `.struct` payload's offset.
        let imageStructOffset = try required(imageWrapper.struct).offset
        let imageCtxStructOffset = try required(imageCtxWrapper.struct).offset
        #expect(imageStructOffset == imageCtxStructOffset)
    }
}
