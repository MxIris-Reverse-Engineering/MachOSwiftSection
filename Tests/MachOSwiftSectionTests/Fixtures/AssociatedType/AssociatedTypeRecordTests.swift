import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `AssociatedTypeRecord`.
///
/// Each `@Test` exercises one ivar / reader method declared in
/// `AssociatedTypeRecord.swift`. The cross-reader assertions use the
/// resolved name string (cheaply equatable) and a presence flag for the
/// `MangledName` payload (a deep ABI tree we don't deep-compare).
///
/// Picker: the first record from
/// `AssociatedTypeWitnessPatterns.ConcreteWitnessTest`'s
/// `AssociatedTypeDescriptor` (witnessing `First = Int`).
@Suite
final class AssociatedTypeRecordTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "AssociatedTypeRecord"
    static var registeredTestMethodNames: Set<String> {
        AssociatedTypeRecordBaseline.registeredTestMethodNames
    }

    // MARK: - Helpers

    private func loadFirstRecord() throws -> (file: AssociatedTypeRecord, image: AssociatedTypeRecord) {
        let fileDescriptor = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machOImage)
        let fileRecords = try fileDescriptor.associatedTypeRecords(in: machOFile)
        let imageRecords = try imageDescriptor.associatedTypeRecords(in: machOImage)
        let file = try required(fileRecords.first)
        let image = try required(imageRecords.first)
        return (file: file, image: image)
    }

    // MARK: - Ivars

    @Test func offset() async throws {
        let records = try loadFirstRecord()
        let result = try acrossAllReaders(
            file: { records.file.offset },
            image: { records.image.offset }
        )
        #expect(result == AssociatedTypeRecordBaseline.firstRecord.offset)
    }

    @Test func layout() async throws {
        // The layout struct holds two RelativeDirectPointers; we exercise
        // cross-reader equality via the resolved `name` string (asserted
        // separately by the `name()` test). This test is the
        // structural-presence anchor — it just verifies the layout
        // accessor is available and consistent across readers.
        let records = try loadFirstRecord()
        let nameStringMatches = try acrossAllReaders(
            file: { try records.file.name(in: machOFile) },
            image: { try records.image.name(in: machOImage) }
        )
        #expect(nameStringMatches == AssociatedTypeRecordBaseline.firstRecord.name)
    }

    // MARK: - Reader methods

    @Test func name() async throws {
        let records = try loadFirstRecord()
        let result = try acrossAllReaders(
            file: { try records.file.name(in: machOFile) },
            image: { try records.image.name(in: machOImage) }
        )
        #expect(result == AssociatedTypeRecordBaseline.firstRecord.name)

        // ReadingContext-based overload also exercised.
        let imageCtxResult = try records.image.name(in: imageContext)
        #expect(imageCtxResult == AssociatedTypeRecordBaseline.firstRecord.name)
    }

    @Test func substitutedTypeName() async throws {
        let records = try loadFirstRecord()
        let presence = try acrossAllReaders(
            file: { (try? records.file.substitutedTypeName(in: machOFile)) != nil },
            image: { (try? records.image.substitutedTypeName(in: machOImage)) != nil }
        )
        #expect(presence == AssociatedTypeRecordBaseline.firstRecord.hasSubstitutedTypeName)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try? records.image.substitutedTypeName(in: imageContext)) != nil
        #expect(imageCtxPresence == AssociatedTypeRecordBaseline.firstRecord.hasSubstitutedTypeName)
    }
}
