import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `Struct` (the high-level wrapper around
/// `StructDescriptor`).
///
/// Each `@Test` exercises one ivar / initializer of `Struct`. The cross-
/// reader assertions use *presence* (whether the optional is set, the
/// element count for arrays, the descriptor offset for nested descriptors)
/// because the heavy types (`TypeGenericContext`, `SingletonMetadataPointer`,
/// etc.) don't satisfy `Equatable` cheaply and would force ad-hoc adapters.
/// Presence + cardinality is the meaningful invariant: it fails if a reader
/// disagrees about whether a field exists, which is what we care about.
///
/// `init(descriptor:in:)` (over the file and image contexts and the
/// in-process context) is exercised by the same tests that instantiate the
/// `Struct`; we surface explicit `@Test func init...` entries for coverage
/// purposes.
@Suite
@FixtureSuite
final class StructTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// Helper: instantiate the `Struct` wrapper for `Structs.StructTest` against
    /// both the file and image readers through their reading contexts.
    /// Used by every ivar test — the file/image-context and in-process
    /// initializer paths are exercised separately by `initializerWithMachO()`
    /// / `initializerInProcess()`.
    private func loadStructTestStructs() throws -> (file: Struct, image: Struct) {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let file = try Struct(descriptor: fileDescriptor, in: fileContext)
        let image = try Struct(descriptor: imageDescriptor, in: imageContext)
        return (file: file, image: image)
    }

    // MARK: - Initializers

    @Test("init(descriptor:in:)") func initializerWithMachO() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        // Both file/image context-based initializers must succeed and produce
        // a descriptor whose offset matches the baseline.
        let fileStruct = try Struct(descriptor: fileDescriptor, in: fileContext)
        let imageStruct = try Struct(descriptor: imageDescriptor, in: imageContext)

        #expect(fileStruct.descriptor.offset == StructBaseline.structTest.descriptorOffset)
        #expect(imageStruct.descriptor.offset == StructBaseline.structTest.descriptorOffset)
    }

    @Test("init(descriptor:)") func initializerInProcess() async throws {
        // Initializing through `inProcessContext` requires a pointer-form
        // descriptor resolved against MachOImage; reproduce that here.
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let pointerDescriptor = imageDescriptor.asPointerWrapper(in: machOImage)
        let inProcessStruct = try Struct(descriptor: pointerDescriptor, in: inProcessContext)

        // The in-process `descriptor.offset` is a pointer bit pattern, not a
        // file offset — we just assert a non-zero offset (i.e. resolution
        // succeeded), since the absolute pointer is per-process.
        #expect(inProcessStruct.descriptor.offset != 0)
    }

    // MARK: - Ivars

    @Test func descriptor() async throws {
        let structs = try loadStructTestStructs()

        let descriptorOffsets = try acrossAllReaders(structs.file, structs.image) { $0.descriptor.offset }
        #expect(descriptorOffsets == StructBaseline.structTest.descriptorOffset)
    }

    @Test func genericContext() async throws {
        // Concrete struct (`StructTest`): no generic context.
        let structs = try loadStructTestStructs()
        let structTestPresence = try acrossAllReaders(structs.file, structs.image) { $0.genericContext != nil }
        #expect(structTestPresence == StructBaseline.structTest.hasGenericContext)

        // Generic struct (`GenericStructNonRequirement<A>`): has a generic context.
        let genericFile = try Struct(
            descriptor: try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machOFile),
            in: fileContext
        )
        let genericImage = try Struct(
            descriptor: try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machOImage),
            in: imageContext
        )
        let genericPresence = try acrossAllReaders(genericFile, genericImage) { $0.genericContext != nil }
        #expect(genericPresence == StructBaseline.genericStructNonRequirement.hasGenericContext)
    }

    @Test func foreignMetadataInitialization() async throws {
        let structs = try loadStructTestStructs()
        let presence = try acrossAllReaders(structs.file, structs.image) { $0.foreignMetadataInitialization != nil }
        #expect(presence == StructBaseline.structTest.hasForeignMetadataInitialization)
    }

    @Test func singletonMetadataInitialization() async throws {
        let structs = try loadStructTestStructs()
        let presence = try acrossAllReaders(structs.file, structs.image) { $0.singletonMetadataInitialization != nil }
        #expect(presence == StructBaseline.structTest.hasSingletonMetadataInitialization)
    }

    @Test func canonicalSpecializedMetadatas() async throws {
        let structs = try loadStructTestStructs()
        let count = try acrossAllReaders(structs.file, structs.image) { $0.canonicalSpecializedMetadatas.count }
        #expect(count == StructBaseline.structTest.canonicalSpecializedMetadatasCount)
    }

    @Test func canonicalSpecializedMetadatasListCount() async throws {
        let structs = try loadStructTestStructs()
        let presence = try acrossAllReaders(structs.file, structs.image) { $0.canonicalSpecializedMetadatasListCount != nil }
        #expect(presence == StructBaseline.structTest.hasCanonicalSpecializedMetadatasListCount)
    }

    @Test func canonicalSpecializedMetadatasCachingOnceToken() async throws {
        let structs = try loadStructTestStructs()
        let presence = try acrossAllReaders(structs.file, structs.image) { swiftStruct in
            swiftStruct.canonicalSpecializedMetadatasCachingOnceToken != nil
        }
        #expect(presence == StructBaseline.structTest.hasCanonicalSpecializedMetadatasCachingOnceToken)
    }

    @Test func invertibleProtocolSet() async throws {
        let structs = try loadStructTestStructs()
        let presence = try acrossAllReaders(structs.file, structs.image) { $0.invertibleProtocolSet != nil }
        #expect(presence == StructBaseline.structTest.hasInvertibleProtocolSet)
    }

    @Test func singletonMetadataPointer() async throws {
        let structs = try loadStructTestStructs()
        let presence = try acrossAllReaders(structs.file, structs.image) { $0.singletonMetadataPointer != nil }
        #expect(presence == StructBaseline.structTest.hasSingletonMetadataPointer)
    }
}
