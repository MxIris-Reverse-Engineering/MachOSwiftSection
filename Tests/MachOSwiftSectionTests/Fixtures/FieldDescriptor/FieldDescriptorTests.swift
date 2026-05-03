import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `FieldDescriptor`.
///
/// Each `@Test` exercises one ivar / derived var / reader method declared
/// in `FieldDescriptor.swift`. The cross-reader assertions use
/// counts/presence flags rather than full structural equality — `MangledName`
/// payloads parse to deep ABI trees that we don't deep-compare; presence
/// + cardinality is the meaningful invariant.
///
/// Fixture variants:
///   - `genericStructNonRequirement` — three records (`field1`, `field2`,
///     `field3`)
///   - `structTest` — zero records (StructTest declares only a computed
///     property, no stored fields)
@Suite
final class FieldDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "FieldDescriptor"
    static var registeredTestMethodNames: Set<String> {
        FieldDescriptorBaseline.registeredTestMethodNames
    }

    // MARK: - Helpers

    private func loadGenericStructFieldDescriptors() throws -> (file: FieldDescriptor, image: FieldDescriptor) {
        let fileDescriptor = try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machOImage)
        let file = try required(try fileDescriptor.fieldDescriptor(in: machOFile))
        let image = try required(try imageDescriptor.fieldDescriptor(in: machOImage))
        return (file: file, image: image)
    }

    private func loadStructTestFieldDescriptors() throws -> (file: FieldDescriptor, image: FieldDescriptor) {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let file = try required(try fileDescriptor.fieldDescriptor(in: machOFile))
        let image = try required(try imageDescriptor.fieldDescriptor(in: machOImage))
        return (file: file, image: image)
    }

    // MARK: - Ivars

    @Test func offset() async throws {
        let descriptors = try loadGenericStructFieldDescriptors()
        let result = try acrossAllReaders(
            file: { descriptors.file.offset },
            image: { descriptors.image.offset }
        )
        #expect(result == FieldDescriptorBaseline.genericStructNonRequirement.offset)
    }

    @Test func layout() async throws {
        // Cross-reader equality on the per-field layout values
        // (numFields and fieldRecordSize, kind via raw value).
        let descriptors = try loadGenericStructFieldDescriptors()
        let numFields = try acrossAllReaders(
            file: { Int(descriptors.file.layout.numFields) },
            image: { Int(descriptors.image.layout.numFields) }
        )
        #expect(numFields == FieldDescriptorBaseline.genericStructNonRequirement.layoutNumFields)

        let fieldRecordSize = try acrossAllReaders(
            file: { Int(descriptors.file.layout.fieldRecordSize) },
            image: { Int(descriptors.image.layout.fieldRecordSize) }
        )
        #expect(fieldRecordSize == FieldDescriptorBaseline.genericStructNonRequirement.layoutFieldRecordSize)

        let kindRaw = try acrossAllReaders(
            file: { descriptors.file.layout.kind },
            image: { descriptors.image.layout.kind }
        )
        #expect(kindRaw == FieldDescriptorBaseline.genericStructNonRequirement.kindRawValue)
    }

    // MARK: - Derived var

    @Test func kind() async throws {
        let descriptors = try loadGenericStructFieldDescriptors()
        let result = try acrossAllReaders(
            file: { descriptors.file.kind.rawValue },
            image: { descriptors.image.kind.rawValue }
        )
        #expect(result == FieldDescriptorBaseline.genericStructNonRequirement.kindRawValue)
    }

    // MARK: - Reader methods

    @Test func mangledTypeName() async throws {
        let descriptors = try loadGenericStructFieldDescriptors()
        let presence = try acrossAllReaders(
            file: { (try? descriptors.file.mangledTypeName(in: machOFile)) != nil },
            image: { (try? descriptors.image.mangledTypeName(in: machOImage)) != nil }
        )
        #expect(presence == FieldDescriptorBaseline.genericStructNonRequirement.hasMangledTypeName)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try? descriptors.image.mangledTypeName(in: imageContext)) != nil
        #expect(imageCtxPresence == FieldDescriptorBaseline.genericStructNonRequirement.hasMangledTypeName)
    }

    @Test func records() async throws {
        // Fixture with non-empty records: GenericStructNonRequirement (3 fields).
        let genericDescriptors = try loadGenericStructFieldDescriptors()
        let genericCount = try acrossAllReaders(
            file: { try genericDescriptors.file.records(in: machOFile).count },
            image: { try genericDescriptors.image.records(in: machOImage).count }
        )
        #expect(genericCount == FieldDescriptorBaseline.genericStructNonRequirement.recordsCount)

        // ReadingContext-based overload also exercised.
        let imageCtxCount = try genericDescriptors.image.records(in: imageContext).count
        #expect(imageCtxCount == FieldDescriptorBaseline.genericStructNonRequirement.recordsCount)

        // Fixture with empty records: StructTest (0 fields, only a computed body).
        let structTestDescriptors = try loadStructTestFieldDescriptors()
        let structTestCount = try acrossAllReaders(
            file: { try structTestDescriptors.file.records(in: machOFile).count },
            image: { try structTestDescriptors.image.records(in: machOImage).count }
        )
        #expect(structTestCount == FieldDescriptorBaseline.structTest.recordsCount)
    }
}
