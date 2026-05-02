import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `Enum` (the high-level wrapper around
/// `EnumDescriptor`).
///
/// Each `@Test` exercises one ivar / initializer of `Enum`. The cross-
/// reader assertions use **presence/cardinality** (whether the optional
/// is set, the element count for arrays, the descriptor offset for nested
/// descriptors) because the heavy types (`TypeGenericContext`,
/// `SingletonMetadataPointer`, etc.) don't satisfy `Equatable` cheaply.
///
/// `init(descriptor:in:)` (MachO + ReadingContext overloads) and
/// `init(descriptor:)` (in-process) are exercised by dedicated tests.
@Suite
final class EnumTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "Enum"
    static var registeredTestMethodNames: Set<String> {
        EnumBaseline.registeredTestMethodNames
    }

    /// Helper: instantiate the `Enum` wrapper for `Enums.NoPayloadEnumTest`
    /// against both readers using the MachO-direct initializer.
    private func loadNoPayloadEnums() throws -> (file: Enum, image: Enum) {
        let fileDescriptor = try BaselineFixturePicker.enum_NoPayloadEnumTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.enum_NoPayloadEnumTest(in: machOImage)
        let file = try Enum(descriptor: fileDescriptor, in: machOFile)
        let image = try Enum(descriptor: imageDescriptor, in: machOImage)
        return (file: file, image: image)
    }

    // MARK: - Initializers

    @Test("init(descriptor:in:)") func initializerWithMachO() async throws {
        let fileDescriptor = try BaselineFixturePicker.enum_NoPayloadEnumTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.enum_NoPayloadEnumTest(in: machOImage)

        let fileEnum = try Enum(descriptor: fileDescriptor, in: machOFile)
        let imageEnum = try Enum(descriptor: imageDescriptor, in: machOImage)
        let fileCtxEnum = try Enum(descriptor: fileDescriptor, in: fileContext)
        let imageCtxEnum = try Enum(descriptor: imageDescriptor, in: imageContext)

        #expect(fileEnum.descriptor.offset == EnumBaseline.noPayloadEnumTest.descriptorOffset)
        #expect(imageEnum.descriptor.offset == EnumBaseline.noPayloadEnumTest.descriptorOffset)
        #expect(fileCtxEnum.descriptor.offset == EnumBaseline.noPayloadEnumTest.descriptorOffset)
        #expect(imageCtxEnum.descriptor.offset == EnumBaseline.noPayloadEnumTest.descriptorOffset)
    }

    @Test("init(descriptor:)") func initializerInProcess() async throws {
        let imageDescriptor = try BaselineFixturePicker.enum_NoPayloadEnumTest(in: machOImage)
        let pointerDescriptor = imageDescriptor.asPointerWrapper(in: machOImage)
        let inProcessEnum = try Enum(descriptor: pointerDescriptor)

        // The in-process `descriptor.offset` is a pointer bit pattern.
        #expect(inProcessEnum.descriptor.offset != 0)
    }

    // MARK: - Ivars (NoPayloadEnumTest path)

    @Test func descriptor() async throws {
        let enums = try loadNoPayloadEnums()
        let descriptorOffsets = try acrossAllReaders(
            file: { enums.file.descriptor.offset },
            image: { enums.image.descriptor.offset }
        )
        #expect(descriptorOffsets == EnumBaseline.noPayloadEnumTest.descriptorOffset)
    }

    @Test func genericContext() async throws {
        let enums = try loadNoPayloadEnums()
        let presence = try acrossAllReaders(
            file: { enums.file.genericContext != nil },
            image: { enums.image.genericContext != nil }
        )
        #expect(presence == EnumBaseline.noPayloadEnumTest.hasGenericContext)
    }

    @Test func foreignMetadataInitialization() async throws {
        let enums = try loadNoPayloadEnums()
        let presence = try acrossAllReaders(
            file: { enums.file.foreignMetadataInitialization != nil },
            image: { enums.image.foreignMetadataInitialization != nil }
        )
        #expect(presence == EnumBaseline.noPayloadEnumTest.hasForeignMetadataInitialization)
    }

    @Test func singletonMetadataInitialization() async throws {
        let enums = try loadNoPayloadEnums()
        let presence = try acrossAllReaders(
            file: { enums.file.singletonMetadataInitialization != nil },
            image: { enums.image.singletonMetadataInitialization != nil }
        )
        #expect(presence == EnumBaseline.noPayloadEnumTest.hasSingletonMetadataInitialization)
    }

    @Test func canonicalSpecializedMetadatas() async throws {
        let enums = try loadNoPayloadEnums()
        let count = try acrossAllReaders(
            file: { enums.file.canonicalSpecializedMetadatas.count },
            image: { enums.image.canonicalSpecializedMetadatas.count }
        )
        #expect(count == EnumBaseline.noPayloadEnumTest.canonicalSpecializedMetadatasCount)
    }

    @Test func canonicalSpecializedMetadatasListCount() async throws {
        let enums = try loadNoPayloadEnums()
        let presence = try acrossAllReaders(
            file: { enums.file.canonicalSpecializedMetadatasListCount != nil },
            image: { enums.image.canonicalSpecializedMetadatasListCount != nil }
        )
        #expect(presence == EnumBaseline.noPayloadEnumTest.hasCanonicalSpecializedMetadatasListCount)
    }

    @Test func canonicalSpecializedMetadatasCachingOnceToken() async throws {
        let enums = try loadNoPayloadEnums()
        let presence = try acrossAllReaders(
            file: { enums.file.canonicalSpecializedMetadatasCachingOnceToken != nil },
            image: { enums.image.canonicalSpecializedMetadatasCachingOnceToken != nil }
        )
        #expect(presence == EnumBaseline.noPayloadEnumTest.hasCanonicalSpecializedMetadatasCachingOnceToken)
    }

    @Test func invertibleProtocolSet() async throws {
        let enums = try loadNoPayloadEnums()
        let presence = try acrossAllReaders(
            file: { enums.file.invertibleProtocolSet != nil },
            image: { enums.image.invertibleProtocolSet != nil }
        )
        #expect(presence == EnumBaseline.noPayloadEnumTest.hasInvertibleProtocolSet)
    }

    @Test func singletonMetadataPointer() async throws {
        let enums = try loadNoPayloadEnums()
        let presence = try acrossAllReaders(
            file: { enums.file.singletonMetadataPointer != nil },
            image: { enums.image.singletonMetadataPointer != nil }
        )
        #expect(presence == EnumBaseline.noPayloadEnumTest.hasSingletonMetadataPointer)
    }
}
