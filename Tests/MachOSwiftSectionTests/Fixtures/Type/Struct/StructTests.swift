import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

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
/// `init(descriptor:in:)` (MachO + ReadingContext overloads) and
/// `init(descriptor:)` (in-process) are exercised by the same tests that
/// instantiate the `Struct`; we surface explicit `@Test func init...` entries
/// for coverage purposes.
@Suite
final class StructTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "Struct"
    static var registeredTestMethodNames: Set<String> {
        StructBaseline.registeredTestMethodNames
    }

    // MARK: - Initializers

    @Test("init(descriptor:in:)") func initializerWithMachO() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        // Both file/image MachO-based initializers must succeed and produce a
        // descriptor whose offset matches the baseline.
        let fileStruct = try Struct(descriptor: fileDescriptor, in: machOFile)
        let imageStruct = try Struct(descriptor: imageDescriptor, in: machOImage)
        let fileCtxStruct = try Struct(descriptor: fileDescriptor, in: fileContext)
        let imageCtxStruct = try Struct(descriptor: imageDescriptor, in: imageContext)

        #expect(fileStruct.descriptor.offset == StructBaseline.structTest.descriptorOffset)
        #expect(imageStruct.descriptor.offset == StructBaseline.structTest.descriptorOffset)
        #expect(fileCtxStruct.descriptor.offset == StructBaseline.structTest.descriptorOffset)
        #expect(imageCtxStruct.descriptor.offset == StructBaseline.structTest.descriptorOffset)
    }

    @Test("init(descriptor:)") func initializerInProcess() async throws {
        // The InProcess `init(descriptor:)` requires a pointer-form descriptor
        // resolved against MachOImage; reproduce that here.
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let pointerDescriptor = imageDescriptor.asPointerWrapper(in: machOImage)
        let inProcessStruct = try Struct(descriptor: pointerDescriptor)

        // The in-process `descriptor.offset` is a pointer bit pattern, not a
        // file offset — we just assert a non-zero offset (i.e. resolution
        // succeeded), since the absolute pointer is per-process.
        #expect(inProcessStruct.descriptor.offset != 0)
    }

    // MARK: - Ivars

    @Test func descriptor() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let fileStruct = try Struct(descriptor: fileDescriptor, in: machOFile)
        let imageStruct = try Struct(descriptor: imageDescriptor, in: machOImage)

        let descriptorOffsets = try acrossAllReaders(
            file: { fileStruct.descriptor.offset },
            image: { imageStruct.descriptor.offset }
        )
        #expect(descriptorOffsets == StructBaseline.structTest.descriptorOffset)
    }

    @Test func genericContext() async throws {
        // Concrete struct (`StructTest`): no generic context.
        let structTestFile = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOFile),
            in: machOFile
        )
        let structTestImage = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOImage),
            in: machOImage
        )
        let structTestPresence = try acrossAllReaders(
            file: { structTestFile.genericContext != nil },
            image: { structTestImage.genericContext != nil }
        )
        #expect(structTestPresence == StructBaseline.structTest.hasGenericContext)

        // Generic struct (`GenericStructNonRequirement<A>`): has a generic context.
        let genericFile = try Struct(
            descriptor: try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machOFile),
            in: machOFile
        )
        let genericImage = try Struct(
            descriptor: try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machOImage),
            in: machOImage
        )
        let genericPresence = try acrossAllReaders(
            file: { genericFile.genericContext != nil },
            image: { genericImage.genericContext != nil }
        )
        #expect(genericPresence == StructBaseline.genericStructNonRequirement.hasGenericContext)
    }

    @Test func foreignMetadataInitialization() async throws {
        let fileStruct = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOFile),
            in: machOFile
        )
        let imageStruct = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOImage),
            in: machOImage
        )
        let presence = try acrossAllReaders(
            file: { fileStruct.foreignMetadataInitialization != nil },
            image: { imageStruct.foreignMetadataInitialization != nil }
        )
        #expect(presence == StructBaseline.structTest.hasForeignMetadataInitialization)
    }

    @Test func singletonMetadataInitialization() async throws {
        let fileStruct = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOFile),
            in: machOFile
        )
        let imageStruct = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOImage),
            in: machOImage
        )
        let presence = try acrossAllReaders(
            file: { fileStruct.singletonMetadataInitialization != nil },
            image: { imageStruct.singletonMetadataInitialization != nil }
        )
        #expect(presence == StructBaseline.structTest.hasSingletonMetadataInitialization)
    }

    @Test func canonicalSpecializedMetadatas() async throws {
        let fileStruct = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOFile),
            in: machOFile
        )
        let imageStruct = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOImage),
            in: machOImage
        )
        let count = try acrossAllReaders(
            file: { fileStruct.canonicalSpecializedMetadatas.count },
            image: { imageStruct.canonicalSpecializedMetadatas.count }
        )
        #expect(count == StructBaseline.structTest.canonicalSpecializedMetadatasCount)
    }

    @Test func canonicalSpecializedMetadatasListCount() async throws {
        let fileStruct = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOFile),
            in: machOFile
        )
        let imageStruct = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOImage),
            in: machOImage
        )
        let presence = try acrossAllReaders(
            file: { fileStruct.canonicalSpecializedMetadatasListCount != nil },
            image: { imageStruct.canonicalSpecializedMetadatasListCount != nil }
        )
        #expect(presence == StructBaseline.structTest.hasCanonicalSpecializedMetadatasListCount)
    }

    @Test func canonicalSpecializedMetadatasCachingOnceToken() async throws {
        let fileStruct = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOFile),
            in: machOFile
        )
        let imageStruct = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOImage),
            in: machOImage
        )
        let presence = try acrossAllReaders(
            file: { fileStruct.canonicalSpecializedMetadatasCachingOnceToken != nil },
            image: { imageStruct.canonicalSpecializedMetadatasCachingOnceToken != nil }
        )
        #expect(presence == StructBaseline.structTest.hasCanonicalSpecializedMetadatasCachingOnceToken)
    }

    @Test func invertibleProtocolSet() async throws {
        let fileStruct = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOFile),
            in: machOFile
        )
        let imageStruct = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOImage),
            in: machOImage
        )
        let presence = try acrossAllReaders(
            file: { fileStruct.invertibleProtocolSet != nil },
            image: { imageStruct.invertibleProtocolSet != nil }
        )
        #expect(presence == StructBaseline.structTest.hasInvertibleProtocolSet)
    }

    @Test func singletonMetadataPointer() async throws {
        let fileStruct = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOFile),
            in: machOFile
        )
        let imageStruct = try Struct(
            descriptor: try BaselineFixturePicker.struct_StructTest(in: machOImage),
            in: machOImage
        )
        let presence = try acrossAllReaders(
            file: { fileStruct.singletonMetadataPointer != nil },
            image: { imageStruct.singletonMetadataPointer != nil }
        )
        #expect(presence == StructBaseline.structTest.hasSingletonMetadataPointer)
    }
}
