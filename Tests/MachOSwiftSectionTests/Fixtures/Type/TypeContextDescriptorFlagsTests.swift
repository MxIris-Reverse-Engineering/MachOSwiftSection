import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `TypeContextDescriptorFlags`.
///
/// `TypeContextDescriptorFlags` is the kind-specific 16-bit `FlagSet`
/// reachable via `ContextDescriptorFlags.kindSpecificFlags?.typeFlags`.
/// We exercise it against two pickers so each branch is witnessed:
///   - `Structs.StructTest` for the kind-agnostic accessors and to confirm
///     the class-only flags read as `false` for non-class kinds.
///   - `Classes.ClassTest` for the class-specific accessors (so
///     `classHasVTable` and friends have a real-world value to assert).
@Suite
@FixtureSuite
final class TypeContextDescriptorFlagsTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadStructTestFlags() throws -> (file: TypeContextDescriptorFlags, image: TypeContextDescriptorFlags) {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let file = try required(fileDescriptor.layout.flags.kindSpecificFlags?.typeFlags)
        let image = try required(imageDescriptor.layout.flags.kindSpecificFlags?.typeFlags)
        return (file: file, image: image)
    }

    private func loadClassTestFlags() throws -> (file: TypeContextDescriptorFlags, image: TypeContextDescriptorFlags) {
        let fileDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let file = try required(fileDescriptor.layout.flags.kindSpecificFlags?.typeFlags)
        let image = try required(imageDescriptor.layout.flags.kindSpecificFlags?.typeFlags)
        return (file: file, image: image)
    }

    @Test func rawValue() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.rawValue }
        #expect(result == TypeContextDescriptorFlagsBaseline.structTest.rawValue)
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        // Round-trip construction: `init(rawValue:)` must reproduce the
        // baseline's stored rawValue verbatim, and the derived accessors
        // must match the live extraction. Use the class-test entry so
        // class-only flags are non-zero (`classHasVTable: true`).
        let constructed = TypeContextDescriptorFlags(
            rawValue: TypeContextDescriptorFlagsBaseline.classTest.rawValue
        )
        #expect(constructed.rawValue == TypeContextDescriptorFlagsBaseline.classTest.rawValue)
        #expect(constructed.classHasVTable == TypeContextDescriptorFlagsBaseline.classTest.classHasVTable)
        #expect(constructed.noMetadataInitialization == TypeContextDescriptorFlagsBaseline.classTest.noMetadataInitialization)
    }

    // MARK: - Metadata-initialization accessors (StructTest witnesses)

    @Test func noMetadataInitialization() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.noMetadataInitialization }
        #expect(result == TypeContextDescriptorFlagsBaseline.structTest.noMetadataInitialization)
    }

    @Test func hasSingletonMetadataInitialization() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.hasSingletonMetadataInitialization }
        #expect(result == TypeContextDescriptorFlagsBaseline.structTest.hasSingletonMetadataInitialization)
    }

    @Test func hasForeignMetadataInitialization() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.hasForeignMetadataInitialization }
        #expect(result == TypeContextDescriptorFlagsBaseline.structTest.hasForeignMetadataInitialization)
    }

    // MARK: - Generic-flag accessors (StructTest witnesses)

    @Test func hasImportInfo() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.hasImportInfo }
        #expect(result == TypeContextDescriptorFlagsBaseline.structTest.hasImportInfo)
    }

    @Test func hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { descriptorFlags in
            descriptorFlags.hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer
        }
        #expect(result == TypeContextDescriptorFlagsBaseline.structTest.hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer)
    }

    @Test func hasLayoutString() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.hasLayoutString }
        #expect(result == TypeContextDescriptorFlagsBaseline.structTest.hasLayoutString)
    }

    // MARK: - Class-specific accessors (ClassTest witnesses)

    @Test func classHasDefaultOverrideTable() async throws {
        let flags = try loadClassTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.classHasDefaultOverrideTable }
        #expect(result == TypeContextDescriptorFlagsBaseline.classTest.classHasDefaultOverrideTable)
    }

    @Test func classIsActor() async throws {
        let flags = try loadClassTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.classIsActor }
        #expect(result == TypeContextDescriptorFlagsBaseline.classTest.classIsActor)
    }

    @Test func classIsDefaultActor() async throws {
        let flags = try loadClassTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.classIsDefaultActor }
        #expect(result == TypeContextDescriptorFlagsBaseline.classTest.classIsDefaultActor)
    }

    @Test func classResilientSuperclassReferenceKind() async throws {
        let flags = try loadClassTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.classResilientSuperclassReferenceKind?.rawValue }
        #expect(result == TypeContextDescriptorFlagsBaseline.classTest.classResilientSuperclassReferenceKindRawValue)
    }

    @Test func classAreImmdiateMembersNegative() async throws {
        let flags = try loadClassTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.classAreImmdiateMembersNegative }
        #expect(result == TypeContextDescriptorFlagsBaseline.classTest.classAreImmdiateMembersNegative)
    }

    @Test func classHasResilientSuperclass() async throws {
        let flags = try loadClassTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.classHasResilientSuperclass }
        #expect(result == TypeContextDescriptorFlagsBaseline.classTest.classHasResilientSuperclass)
    }

    @Test func classHasOverrideTable() async throws {
        let flags = try loadClassTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.classHasOverrideTable }
        #expect(result == TypeContextDescriptorFlagsBaseline.classTest.classHasOverrideTable)
    }

    /// Witnessed by `Classes.ClassTest` (a non-trivial class) — its kind-
    /// specific flags carry the high bit (`classHasVTable: true`).
    @Test func classHasVTable() async throws {
        let flags = try loadClassTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.classHasVTable }
        #expect(result == TypeContextDescriptorFlagsBaseline.classTest.classHasVTable)
    }
}
