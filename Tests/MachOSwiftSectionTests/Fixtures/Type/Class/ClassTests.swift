import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `Class` (the high-level wrapper around
/// `ClassDescriptor`).
///
/// Each `@Test` exercises one ivar / initializer of `Class`. The cross-
/// reader assertions use **presence/cardinality** (whether the optional
/// is set, the element count for arrays, the descriptor offset for nested
/// descriptors) because the heavy types (`TypeGenericContext`,
/// `MethodDescriptor`, etc.) don't satisfy `Equatable` cheaply.
///
/// `init(descriptor:in:)` is exercised by dedicated tests over the file
/// and image contexts and over the in-process context.
@Suite
@FixtureSuite
final class ClassTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// Helper: instantiate the `Class` wrapper for `Classes.ClassTest`
    /// against both readers through their reading contexts.
    private func loadClassTestClasses() throws -> (file: Class, image: Class) {
        let fileDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let file = try Class(descriptor: fileDescriptor, in: fileContext)
        let image = try Class(descriptor: imageDescriptor, in: imageContext)
        return (file: file, image: image)
    }

    /// Helper: instantiate the `Class` wrapper for `Classes.SubclassTest`
    /// against both readers through their reading contexts.
    private func loadSubclassTestClasses() throws -> (file: Class, image: Class) {
        let fileDescriptor = try BaselineFixturePicker.class_SubclassTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_SubclassTest(in: machOImage)
        let file = try Class(descriptor: fileDescriptor, in: fileContext)
        let image = try Class(descriptor: imageDescriptor, in: imageContext)
        return (file: file, image: image)
    }

    // MARK: - Initializers

    @Test("init(descriptor:in:)") func initializerWithMachO() async throws {
        let fileDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)

        let fileClass = try Class(descriptor: fileDescriptor, in: fileContext)
        let imageClass = try Class(descriptor: imageDescriptor, in: imageContext)

        #expect(fileClass.descriptor.offset == ClassBaseline.classTest.descriptorOffset)
        #expect(imageClass.descriptor.offset == ClassBaseline.classTest.descriptorOffset)
    }

    @Test("init(descriptor:)") func initializerInProcess() async throws {
        let imageDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let pointerDescriptor = imageDescriptor.asPointerWrapper(in: machOImage)
        let inProcessClass = try Class(descriptor: pointerDescriptor, in: inProcessContext)

        // The in-process `descriptor.offset` is a pointer bit pattern.
        #expect(inProcessClass.descriptor.offset != 0)
    }

    // MARK: - Ivars (ClassTest path)

    @Test func descriptor() async throws {
        let classes = try loadClassTestClasses()
        let descriptorOffsets = try acrossAllReaders(classes.file, classes.image) { $0.descriptor.offset }
        #expect(descriptorOffsets == ClassBaseline.classTest.descriptorOffset)
    }

    @Test func genericContext() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(classes.file, classes.image) { $0.genericContext != nil }
        #expect(presence == ClassBaseline.classTest.hasGenericContext)
    }

    @Test func resilientSuperclass() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(classes.file, classes.image) { $0.resilientSuperclass != nil }
        #expect(presence == ClassBaseline.classTest.hasResilientSuperclass)
    }

    @Test func foreignMetadataInitialization() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(classes.file, classes.image) { $0.foreignMetadataInitialization != nil }
        #expect(presence == ClassBaseline.classTest.hasForeignMetadataInitialization)
    }

    @Test func singletonMetadataInitialization() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(classes.file, classes.image) { $0.singletonMetadataInitialization != nil }
        #expect(presence == ClassBaseline.classTest.hasSingletonMetadataInitialization)
    }

    @Test func vTableDescriptorHeader() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(classes.file, classes.image) { $0.vTableDescriptorHeader != nil }
        #expect(presence == ClassBaseline.classTest.hasVTableDescriptorHeader)
    }

    @Test func methodDescriptors() async throws {
        let classes = try loadClassTestClasses()
        let count = try acrossAllReaders(classes.file, classes.image) { $0.methodDescriptors.count }
        #expect(count == ClassBaseline.classTest.methodDescriptorsCount)
    }

    @Test func overrideTableHeader() async throws {
        // SubclassTest is the path that exercises this ivar.
        let classes = try loadSubclassTestClasses()
        let presence = try acrossAllReaders(classes.file, classes.image) { $0.overrideTableHeader != nil }
        #expect(presence == ClassBaseline.subclassTest.hasOverrideTableHeader)
    }

    @Test func methodOverrideDescriptors() async throws {
        let classes = try loadSubclassTestClasses()
        let count = try acrossAllReaders(classes.file, classes.image) { $0.methodOverrideDescriptors.count }
        #expect(count == ClassBaseline.subclassTest.methodOverrideDescriptorsCount)
    }

    @Test func objcResilientClassStubInfo() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(classes.file, classes.image) { $0.objcResilientClassStubInfo != nil }
        #expect(presence == ClassBaseline.classTest.hasObjCResilientClassStubInfo)
    }

    @Test func canonicalSpecializedMetadatasListCount() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(classes.file, classes.image) { $0.canonicalSpecializedMetadatasListCount != nil }
        #expect(presence == ClassBaseline.classTest.hasCanonicalSpecializedMetadatasListCount)
    }

    @Test func canonicalSpecializedMetadatas() async throws {
        let classes = try loadClassTestClasses()
        let count = try acrossAllReaders(classes.file, classes.image) { $0.canonicalSpecializedMetadatas.count }
        #expect(count == ClassBaseline.classTest.canonicalSpecializedMetadatasCount)
    }

    @Test func canonicalSpecializedMetadataAccessors() async throws {
        let classes = try loadClassTestClasses()
        let count = try acrossAllReaders(classes.file, classes.image) { $0.canonicalSpecializedMetadataAccessors.count }
        #expect(count == ClassBaseline.classTest.canonicalSpecializedMetadataAccessorsCount)
    }

    @Test func canonicalSpecializedMetadatasCachingOnceToken() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(classes.file, classes.image) { swiftClass in
            swiftClass.canonicalSpecializedMetadatasCachingOnceToken != nil
        }
        #expect(presence == ClassBaseline.classTest.hasCanonicalSpecializedMetadatasCachingOnceToken)
    }

    @Test func invertibleProtocolSet() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(classes.file, classes.image) { $0.invertibleProtocolSet != nil }
        #expect(presence == ClassBaseline.classTest.hasInvertibleProtocolSet)
    }

    @Test func singletonMetadataPointer() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(classes.file, classes.image) { $0.singletonMetadataPointer != nil }
        #expect(presence == ClassBaseline.classTest.hasSingletonMetadataPointer)
    }

    @Test func methodDefaultOverrideTableHeader() async throws {
        let classes = try loadClassTestClasses()
        let presence = try acrossAllReaders(classes.file, classes.image) { $0.methodDefaultOverrideTableHeader != nil }
        #expect(presence == ClassBaseline.classTest.hasMethodDefaultOverrideTableHeader)
    }

    @Test func methodDefaultOverrideDescriptors() async throws {
        let classes = try loadClassTestClasses()
        let count = try acrossAllReaders(classes.file, classes.image) { $0.methodDefaultOverrideDescriptors.count }
        #expect(count == ClassBaseline.classTest.methodDefaultOverrideDescriptorsCount)
    }
}
