import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

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
@FixtureSuite
final class ClassDescriptorTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
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

        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.offset }
        #expect(result == ClassDescriptorBaseline.classTest.offset)
    }

    @Test func layout() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()

        let numFields = try acrossAllReaders(fileSubject, imageSubject) { $0.layout.numFields }
        let fieldOffsetVectorOffset = try acrossAllReaders(fileSubject, imageSubject) { $0.layout.fieldOffsetVectorOffset }
        let numImmediateMembers = try acrossAllReaders(fileSubject, imageSubject) { $0.layout.numImmediateMembers }
        let flagsRaw = try acrossAllReaders(fileSubject, imageSubject) { $0.layout.flags.rawValue }

        #expect(Int(numFields) == ClassDescriptorBaseline.classTest.layoutNumFields)
        #expect(Int(fieldOffsetVectorOffset) == ClassDescriptorBaseline.classTest.layoutFieldOffsetVectorOffset)
        #expect(Int(numImmediateMembers) == ClassDescriptorBaseline.classTest.layoutNumImmediateMembers)
        #expect(flagsRaw == ClassDescriptorBaseline.classTest.layoutFlagsRawValue)
    }

    // MARK: - Boolean predicates (kind-specific flag accessors)

    @Test func hasFieldOffsetVector() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.hasFieldOffsetVector }
        #expect(result == ClassDescriptorBaseline.classTest.hasFieldOffsetVector)
    }

    @Test func hasDefaultOverrideTable() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.hasDefaultOverrideTable }
        #expect(result == ClassDescriptorBaseline.classTest.hasDefaultOverrideTable)
    }

    @Test func isActor() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.isActor }
        #expect(result == ClassDescriptorBaseline.classTest.isActor)
    }

    @Test func isDefaultActor() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.isDefaultActor }
        #expect(result == ClassDescriptorBaseline.classTest.isDefaultActor)
    }

    @Test func hasVTable() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.hasVTable }
        #expect(result == ClassDescriptorBaseline.classTest.hasVTable)
    }

    @Test func hasOverrideTable() async throws {
        // Use SubclassTest here — the override table is exclusive to subclasses.
        let (fileSubject, imageSubject) = try loadSubclassTestDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.hasOverrideTable }
        #expect(result == ClassDescriptorBaseline.subclassTest.hasOverrideTable)
    }

    @Test func hasResilientSuperclass() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.hasResilientSuperclass }
        #expect(result == ClassDescriptorBaseline.classTest.hasResilientSuperclass)
    }

    @Test func areImmediateMembersNegative() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.areImmediateMembersNegative }
        #expect(result == ClassDescriptorBaseline.classTest.areImmediateMembersNegative)
    }

    @Test func hasObjCResilientClassStub() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.hasObjCResilientClassStub }
        #expect(result == ClassDescriptorBaseline.classTest.hasObjCResilientClassStub)
    }

    // MARK: - Derived size scalars

    @Test func immediateMemberSize() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.immediateMemberSize }
        #expect(UInt(result) == ClassDescriptorBaseline.classTest.immediateMemberSize)
    }

    @Test func nonResilientImmediateMembersOffset() async throws {
        let (fileSubject, imageSubject) = try loadClassTestDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.nonResilientImmediateMembersOffset }
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
        let result = try acrossAllReaders(fileSubject, imageSubject) { descriptor in
            descriptor.resilientSuperclassReferenceKind?.rawValue ?? UInt8.max
        }
        // The chain always resolves for class kind; the value should be
        // a valid TypeReferenceKind raw byte.
        #expect(result != UInt8.max)
    }

    /// `resilientMetadataBounds(in:)` only succeeds on classes with a
    /// resilient superclass. For `ClassTest` we only verify the predicate
    /// that rules it out (`hasResilientSuperclass == false`); the method
    /// itself is not called here. The resilient case
    /// (`ResilientClassFixtures.ResilientChild`) is read through the
    /// in-process context by `StoredClassMetadataBoundsTests`.
    @Test func resilientMetadataBounds() async throws {
        let (fileSubject, _) = try loadClassTestDescriptors()
        // Predicate: no resilient superclass.
        #expect(fileSubject.hasResilientSuperclass == false)
    }

    /// `superclassTypeMangledName(in:)` returns nil for `ClassTest` and a
    /// non-nil mangled name for `SubclassTest`.
    @Test func superclassTypeMangledName() async throws {
        let (classTestFile, classTestImage) = try loadClassTestDescriptors()
        let classTestPresence = try acrossAllContexts(classTestFile, classTestImage) { descriptor, context in
            (try descriptor.superclassTypeMangledName(in: context)) != nil
        }
        #expect(classTestPresence == ClassDescriptorBaseline.classTest.hasSuperclassTypeMangledName)

        let (subclassFile, subclassImage) = try loadSubclassTestDescriptors()
        let subclassPresence = try acrossAllContexts(subclassFile, subclassImage) { descriptor, context in
            (try descriptor.superclassTypeMangledName(in: context)) != nil
        }
        #expect(subclassPresence == ClassDescriptorBaseline.subclassTest.hasSuperclassTypeMangledName)
    }
}
