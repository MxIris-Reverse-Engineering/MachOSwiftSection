import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `Class` (the high-level wrapper around
/// `ClassDescriptor`).
///
/// Each `@Test` exercises one ivar / initializer of `Class`. The cross-
/// reader assertions use **presence/cardinality** (whether the optional
/// is set, the element count for arrays, the descriptor offset for nested
/// descriptors) because the heavy types (`TypeGenericContext`,
/// `MethodDescriptor`, etc.) don't satisfy `Equatable` cheaply.
///
/// `init(descriptor:in:)` (MachO + ReadingContext overloads) and
/// `init(descriptor:)` (in-process) are exercised by dedicated tests.
@Suite
final class ClassTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "Class"
    static var registeredTestMethodNames: Set<String> {
        ClassBaseline.registeredTestMethodNames
    }

    /// Helper: instantiate the `Class` wrapper for `Classes.ClassTest`
    /// against both readers using the MachO-direct initializer.
    private func loadClassTestClasses() throws -> (file: Class, image: Class) {
        let fileDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let file = try Class(descriptor: fileDescriptor, in: machOFile)
        let image = try Class(descriptor: imageDescriptor, in: machOImage)
        return (file: file, image: image)
    }

    /// Helper: instantiate the `Class` wrapper for `Classes.SubclassTest`
    /// against both readers using the MachO-direct initializer.
    private func loadSubclassTestClasses() throws -> (file: Class, image: Class) {
        let fileDescriptor = try BaselineFixturePicker.class_SubclassTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_SubclassTest(in: machOImage)
        let file = try Class(descriptor: fileDescriptor, in: machOFile)
        let image = try Class(descriptor: imageDescriptor, in: machOImage)
        return (file: file, image: image)
    }

    // MARK: - Initializers

    @Test("init(descriptor:in:)") func initializerWithMachO() async throws {
        let fileDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)

        let fileClass = try Class(descriptor: fileDescriptor, in: machOFile)
        let imageClass = try Class(descriptor: imageDescriptor, in: machOImage)
        let fileCtxClass = try Class(descriptor: fileDescriptor, in: fileContext)
        let imageCtxClass = try Class(descriptor: imageDescriptor, in: imageContext)

        #expect(fileClass.descriptor.offset == ClassBaseline.classTest.descriptorOffset)
        #expect(imageClass.descriptor.offset == ClassBaseline.classTest.descriptorOffset)
        #expect(fileCtxClass.descriptor.offset == ClassBaseline.classTest.descriptorOffset)
        #expect(imageCtxClass.descriptor.offset == ClassBaseline.classTest.descriptorOffset)
    }

    @Test("init(descriptor:)") func initializerInProcess() async throws {
        let imageDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let pointerDescriptor = imageDescriptor.asPointerWrapper(in: machOImage)
        let inProcessClass = try Class(descriptor: pointerDescriptor)

        // The in-process `descriptor.offset` is a pointer bit pattern.
        #expect(inProcessClass.descriptor.offset != 0)
    }

    // MARK: - Ivars (ClassTest path)

    @Test func descriptor() async throws {
        let classes = try loadClassTestClasses()
        let descriptorOffsets = try acrossAllReaders(
            file: { classes.file.descriptor.offset },
            image: { classes.image.descriptor.offset }
        )
        #expect(descriptorOffsets == ClassBaseline.classTest.descriptorOffset)
    }

    @Test func genericContext() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(
            file: { classes.file.genericContext != nil },
            image: { classes.image.genericContext != nil }
        )
        #expect(presence == ClassBaseline.classTest.hasGenericContext)
    }

    @Test func resilientSuperclass() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(
            file: { classes.file.resilientSuperclass != nil },
            image: { classes.image.resilientSuperclass != nil }
        )
        #expect(presence == ClassBaseline.classTest.hasResilientSuperclass)
    }

    @Test func foreignMetadataInitialization() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(
            file: { classes.file.foreignMetadataInitialization != nil },
            image: { classes.image.foreignMetadataInitialization != nil }
        )
        #expect(presence == ClassBaseline.classTest.hasForeignMetadataInitialization)
    }

    @Test func singletonMetadataInitialization() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(
            file: { classes.file.singletonMetadataInitialization != nil },
            image: { classes.image.singletonMetadataInitialization != nil }
        )
        #expect(presence == ClassBaseline.classTest.hasSingletonMetadataInitialization)
    }

    @Test func vTableDescriptorHeader() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(
            file: { classes.file.vTableDescriptorHeader != nil },
            image: { classes.image.vTableDescriptorHeader != nil }
        )
        #expect(presence == ClassBaseline.classTest.hasVTableDescriptorHeader)
    }

    @Test func methodDescriptors() async throws {
        let classes = try loadClassTestClasses()
        let count = try acrossAllReaders(
            file: { classes.file.methodDescriptors.count },
            image: { classes.image.methodDescriptors.count }
        )
        #expect(count == ClassBaseline.classTest.methodDescriptorsCount)
    }

    @Test func overrideTableHeader() async throws {
        // SubclassTest is the path that exercises this ivar.
        let classes = try loadSubclassTestClasses()
        let presence = try acrossAllReaders(
            file: { classes.file.overrideTableHeader != nil },
            image: { classes.image.overrideTableHeader != nil }
        )
        #expect(presence == ClassBaseline.subclassTest.hasOverrideTableHeader)
    }

    @Test func methodOverrideDescriptors() async throws {
        let classes = try loadSubclassTestClasses()
        let count = try acrossAllReaders(
            file: { classes.file.methodOverrideDescriptors.count },
            image: { classes.image.methodOverrideDescriptors.count }
        )
        #expect(count == ClassBaseline.subclassTest.methodOverrideDescriptorsCount)
    }

    @Test func objcResilientClassStubInfo() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(
            file: { classes.file.objcResilientClassStubInfo != nil },
            image: { classes.image.objcResilientClassStubInfo != nil }
        )
        #expect(presence == ClassBaseline.classTest.hasObjCResilientClassStubInfo)
    }

    @Test func canonicalSpecializedMetadatasListCount() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(
            file: { classes.file.canonicalSpecializedMetadatasListCount != nil },
            image: { classes.image.canonicalSpecializedMetadatasListCount != nil }
        )
        #expect(presence == ClassBaseline.classTest.hasCanonicalSpecializedMetadatasListCount)
    }

    @Test func canonicalSpecializedMetadatas() async throws {
        let classes = try loadClassTestClasses()
        let count = try acrossAllReaders(
            file: { classes.file.canonicalSpecializedMetadatas.count },
            image: { classes.image.canonicalSpecializedMetadatas.count }
        )
        #expect(count == ClassBaseline.classTest.canonicalSpecializedMetadatasCount)
    }

    @Test func canonicalSpecializedMetadataAccessors() async throws {
        let classes = try loadClassTestClasses()
        let count = try acrossAllReaders(
            file: { classes.file.canonicalSpecializedMetadataAccessors.count },
            image: { classes.image.canonicalSpecializedMetadataAccessors.count }
        )
        #expect(count == ClassBaseline.classTest.canonicalSpecializedMetadataAccessorsCount)
    }

    @Test func canonicalSpecializedMetadatasCachingOnceToken() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(
            file: { classes.file.canonicalSpecializedMetadatasCachingOnceToken != nil },
            image: { classes.image.canonicalSpecializedMetadatasCachingOnceToken != nil }
        )
        #expect(presence == ClassBaseline.classTest.hasCanonicalSpecializedMetadatasCachingOnceToken)
    }

    @Test func invertibleProtocolSet() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(
            file: { classes.file.invertibleProtocolSet != nil },
            image: { classes.image.invertibleProtocolSet != nil }
        )
        #expect(presence == ClassBaseline.classTest.hasInvertibleProtocolSet)
    }

    @Test func singletonMetadataPointer() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(
            file: { classes.file.singletonMetadataPointer != nil },
            image: { classes.image.singletonMetadataPointer != nil }
        )
        #expect(presence == ClassBaseline.classTest.hasSingletonMetadataPointer)
    }

    @Test func methodDefaultOverrideTableHeader() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(
            file: { classes.file.methodDefaultOverrideTableHeader != nil },
            image: { classes.image.methodDefaultOverrideTableHeader != nil }
        )
        #expect(presence == ClassBaseline.classTest.hasMethodDefaultOverrideTableHeader)
    }

    @Test func methodDefaultOverrideDescriptors() async throws {
        let classes = try loadClassTestClasses()
        let count = try acrossAllReaders(
            file: { classes.file.methodDefaultOverrideDescriptors.count },
            image: { classes.image.methodDefaultOverrideDescriptors.count }
        )
        #expect(count == ClassBaseline.classTest.methodDefaultOverrideDescriptorsCount)
    }
}
