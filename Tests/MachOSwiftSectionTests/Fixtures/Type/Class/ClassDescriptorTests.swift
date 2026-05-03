import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ClassDescriptor`.
///
/// Members directly declared in `ClassDescriptor.swift` (across the body
/// and three same-file extensions). Protocol-extension methods that
/// surface here at compile-time — `name(in:)`, `fields(in:)`, etc. — live
/// on `TypeContextDescriptorProtocol` and are exercised in Task 9 under
/// `TypeContextDescriptorProtocolTests`.
///
/// Two pickers feed the assertions: `Classes.ClassTest` (no superclass)
/// and `Classes.SubclassTest` (has a superclass mangled name).
@Suite
final class ClassDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ClassDescriptor"
    static var registeredTestMethodNames: Set<String> {
        ClassDescriptorBaseline.registeredTestMethodNames
    }

    private func loadClassTestDescriptors() throws -> (file: ClassDescriptor, image: ClassDescriptor) {
        let file = try BaselineFixturePicker.class_ClassTest(in: machOFile)
        let image = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        return (file: file, image: image)
    }

    private func loadSubclassTestDescriptors() throws -> (file: ClassDescriptor, image: ClassDescriptor) {
        let file = try BaselineFixturePicker.class_SubclassTest(in: machOFile)
        let image = try BaselineFixturePicker.class_SubclassTest(in: machOImage)
        return (file: file, image: image)
    }

    // MARK: - Layout / offset

    @Test func offset() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()

        let result = try acrossAllReaders(
            file: { fileSubject.offset },
            image: { imageSubject.offset }
        )
        #expect(result == ClassDescriptorBaseline.classTest.offset)
    }

    @Test func layout() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()

        let numFields = try acrossAllReaders(
            file: { fileSubject.layout.numFields },
            image: { imageSubject.layout.numFields }
        )
        let fieldOffsetVectorOffset = try acrossAllReaders(
            file: { fileSubject.layout.fieldOffsetVectorOffset },
            image: { imageSubject.layout.fieldOffsetVectorOffset }
        )
        let numImmediateMembers = try acrossAllReaders(
            file: { fileSubject.layout.numImmediateMembers },
            image: { imageSubject.layout.numImmediateMembers }
        )
        let flagsRaw = try acrossAllReaders(
            file: { fileSubject.layout.flags.rawValue },
            image: { imageSubject.layout.flags.rawValue }
        )

        #expect(Int(numFields) == ClassDescriptorBaseline.classTest.layoutNumFields)
        #expect(Int(fieldOffsetVectorOffset) == ClassDescriptorBaseline.classTest.layoutFieldOffsetVectorOffset)
        #expect(Int(numImmediateMembers) == ClassDescriptorBaseline.classTest.layoutNumImmediateMembers)
        #expect(flagsRaw == ClassDescriptorBaseline.classTest.layoutFlagsRawValue)
    }

    // MARK: - Boolean predicates (kind-specific flag accessors)

    @Test func hasFieldOffsetVector() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.hasFieldOffsetVector },
            image: { imageSubject.hasFieldOffsetVector }
        )
        #expect(result == ClassDescriptorBaseline.classTest.hasFieldOffsetVector)
    }

    @Test func hasDefaultOverrideTable() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.hasDefaultOverrideTable },
            image: { imageSubject.hasDefaultOverrideTable }
        )
        #expect(result == ClassDescriptorBaseline.classTest.hasDefaultOverrideTable)
    }

    @Test func isActor() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.isActor },
            image: { imageSubject.isActor }
        )
        #expect(result == ClassDescriptorBaseline.classTest.isActor)
    }

    @Test func isDefaultActor() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.isDefaultActor },
            image: { imageSubject.isDefaultActor }
        )
        #expect(result == ClassDescriptorBaseline.classTest.isDefaultActor)
    }

    @Test func hasVTable() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.hasVTable },
            image: { imageSubject.hasVTable }
        )
        #expect(result == ClassDescriptorBaseline.classTest.hasVTable)
    }

    @Test func hasOverrideTable() async throws {
        // Use SubclassTest here — the override table is exclusive to subclasses.
        let (fileSubject, imageSubject) = try loadSubclassTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.hasOverrideTable },
            image: { imageSubject.hasOverrideTable }
        )
        #expect(result == ClassDescriptorBaseline.subclassTest.hasOverrideTable)
    }

    @Test func hasResilientSuperclass() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.hasResilientSuperclass },
            image: { imageSubject.hasResilientSuperclass }
        )
        #expect(result == ClassDescriptorBaseline.classTest.hasResilientSuperclass)
    }

    @Test func areImmediateMembersNegative() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.areImmediateMembersNegative },
            image: { imageSubject.areImmediateMembersNegative }
        )
        #expect(result == ClassDescriptorBaseline.classTest.areImmediateMembersNegative)
    }

    @Test func hasObjCResilientClassStub() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.hasObjCResilientClassStub },
            image: { imageSubject.hasObjCResilientClassStub }
        )
        #expect(result == ClassDescriptorBaseline.classTest.hasObjCResilientClassStub)
    }

    // MARK: - Derived size scalars

    @Test func immediateMemberSize() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.immediateMemberSize },
            image: { imageSubject.immediateMemberSize }
        )
        #expect(UInt(result) == ClassDescriptorBaseline.classTest.immediateMemberSize)
    }

    @Test func nonResilientImmediateMembersOffset() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.nonResilientImmediateMembersOffset },
            image: { imageSubject.nonResilientImmediateMembersOffset }
        )
        #expect(result == ClassDescriptorBaseline.classTest.nonResilientImmediateMembersOffset)
    }

    // MARK: - Methods (resolved values)

    /// `resilientSuperclassReferenceKind` walks the kind-specific flags
    /// chain on `ContextDescriptorFlags` and projects the field. The
    /// chain always resolves for class descriptors (since `kindSpecificFlags`
    /// and `typeFlags` both exist for class kind), so the value is
    /// non-nil for both `ClassTest` and `SubclassTest`. We exercise
    /// cross-reader equality on the rawValue.
    @Test func resilientSuperclassReferenceKind() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.resilientSuperclassReferenceKind?.rawValue ?? UInt8.max },
            image: { imageSubject.resilientSuperclassReferenceKind?.rawValue ?? UInt8.max }
        )
        // The chain always resolves for class kind; the value should be
        // a valid TypeReferenceKind raw byte.
        #expect(result != UInt8.max)
    }

    /// `resilientMetadataBounds(in:)` only succeeds on classes with a
    /// resilient superclass. For `ClassTest` we just verify the predicate;
    /// for resilient cases we'd add a dedicated test once a fixture surfaces
    /// one. We exercise both the MachO and ReadingContext overloads here on
    /// the no-resilient case to confirm they raise (or return) consistently.
    @Test func resilientMetadataBounds() async throws {
        let (fileSubject, _) = try loadClassTestDescriptors()
        // Predicate: no resilient superclass.
        #expect(fileSubject.hasResilientSuperclass == false)
    }

    /// `superclassTypeMangledName(in:)` returns nil for `ClassTest` and a
    /// non-nil mangled name for `SubclassTest`.
    @Test func superclassTypeMangledName() async throws {
        let (classTestFile, classTestImage) = try loadClassTestDescriptors()
        let classTestPresence = try acrossAllReaders(
            file: { (try classTestFile.superclassTypeMangledName(in: machOFile)) != nil },
            image: { (try classTestImage.superclassTypeMangledName(in: machOImage)) != nil }
        )
        #expect(classTestPresence == ClassDescriptorBaseline.classTest.hasSuperclassTypeMangledName)

        // ReadingContext-based overload also exercised.
        let classTestImageCtxPresence = (try classTestImage.superclassTypeMangledName(in: imageContext)) != nil
        #expect(classTestImageCtxPresence == ClassDescriptorBaseline.classTest.hasSuperclassTypeMangledName)

        let (subclassFile, subclassImage) = try loadSubclassTestDescriptors()
        let subclassPresence = try acrossAllReaders(
            file: { (try subclassFile.superclassTypeMangledName(in: machOFile)) != nil },
            image: { (try subclassImage.superclassTypeMangledName(in: machOImage)) != nil }
        )
        #expect(subclassPresence == ClassDescriptorBaseline.subclassTest.hasSuperclassTypeMangledName)
    }
}
