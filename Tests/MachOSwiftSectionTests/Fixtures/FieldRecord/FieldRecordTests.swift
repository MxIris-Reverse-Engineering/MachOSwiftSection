import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `FieldRecord`.
///
/// Each `@Test` exercises one ivar / reader method declared in
/// `FieldRecord.swift`. The cross-reader assertions use the resolved
/// field-name string (cheaply equatable) and a presence flag for the
/// `MangledName` payload (a deep ABI tree we don't deep-compare).
///
/// Picker: `GenericStructNonRequirement<A>`'s field descriptor surfaces
/// three records (`field1: Double`, `field2: A`, `field3: Int`). We pin
/// the first two to exercise both a concrete-type field and a
/// generic-parameter field.
@Suite
final class FieldRecordTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "FieldRecord"
    static var registeredTestMethodNames: Set<String> {
        FieldRecordBaseline.registeredTestMethodNames
    }

    // MARK: - Helpers

    private func loadRecords() throws -> (file: [FieldRecord], image: [FieldRecord]) {
        let fileDescriptor = try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machOImage)
        let fileFieldDescriptor = try required(try fileDescriptor.fieldDescriptor(in: machOFile))
        let imageFieldDescriptor = try required(try imageDescriptor.fieldDescriptor(in: machOImage))
        let fileRecords = try fileFieldDescriptor.records(in: machOFile)
        let imageRecords = try imageFieldDescriptor.records(in: machOImage)
        return (file: fileRecords, image: imageRecords)
    }

    private func loadFirstRecord() throws -> (file: FieldRecord, image: FieldRecord) {
        let records = try loadRecords()
        let file = try required(records.file.first)
        let image = try required(records.image.first)
        return (file: file, image: image)
    }

    // MARK: - Ivars

    @Test func offset() async throws {
        let records = try loadFirstRecord()
        let result = try acrossAllReaders(
            file: { records.file.offset },
            image: { records.image.offset }
        )
        #expect(result == FieldRecordBaseline.firstRecord.offset)
    }

    @Test func layout() async throws {
        // Cross-reader equality on the raw flags value (the fixture's
        // records all carry flags == 0x2 — `isVariadic` is set on stored
        // properties).
        let records = try loadFirstRecord()
        let flagsRaw = try acrossAllReaders(
            file: { records.file.layout.flags.rawValue },
            image: { records.image.layout.flags.rawValue }
        )
        #expect(flagsRaw == FieldRecordBaseline.firstRecord.layoutFlagsRawValue)
    }

    // MARK: - Reader methods

    @Test func fieldName() async throws {
        // First record: field1.
        let firstRecords = try loadFirstRecord()
        let firstName = try acrossAllReaders(
            file: { try firstRecords.file.fieldName(in: machOFile) },
            image: { try firstRecords.image.fieldName(in: machOImage) }
        )
        #expect(firstName == FieldRecordBaseline.firstRecord.fieldName)

        // ReadingContext-based overload also exercised.
        let imageCtxFirstName = try firstRecords.image.fieldName(in: imageContext)
        #expect(imageCtxFirstName == FieldRecordBaseline.firstRecord.fieldName)

        // Second record: field2.
        let allRecords = try loadRecords()
        let fileSecond = try required(allRecords.file.dropFirst().first)
        let imageSecond = try required(allRecords.image.dropFirst().first)
        let secondName = try acrossAllReaders(
            file: { try fileSecond.fieldName(in: machOFile) },
            image: { try imageSecond.fieldName(in: machOImage) }
        )
        #expect(secondName == FieldRecordBaseline.secondRecord.fieldName)
    }

    @Test func mangledTypeName() async throws {
        let records = try loadFirstRecord()
        let presence = try acrossAllReaders(
            file: { (try? records.file.mangledTypeName(in: machOFile)) != nil },
            image: { (try? records.image.mangledTypeName(in: machOImage)) != nil }
        )
        #expect(presence == FieldRecordBaseline.firstRecord.hasMangledTypeName)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try? records.image.mangledTypeName(in: imageContext)) != nil
        #expect(imageCtxPresence == FieldRecordBaseline.firstRecord.hasMangledTypeName)
    }
}
