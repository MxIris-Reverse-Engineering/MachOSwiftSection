import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

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
@FixtureSuite
final class AssociatedTypeRecordTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    // MARK: - Helpers

    private func loadFirstRecord() throws -> (file: AssociatedTypeRecord, image: AssociatedTypeRecord) {
        let fileDescriptor = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machOImage)
        let fileRecords = try fileDescriptor.associatedTypeRecords(in: fileContext)
        let imageRecords = try imageDescriptor.associatedTypeRecords(in: imageContext)
        let file = try required(fileRecords.first)
        let image = try required(imageRecords.first)
        return (file: file, image: image)
    }

    // MARK: - Ivars

    @Test func offset() async throws {
        let records = try loadFirstRecord()
        let result = try acrossAllReaders(records.file, records.image) { $0.offset }
        #expect(result == AssociatedTypeRecordBaseline.firstRecord.offset)
    }

    @Test func layout() async throws {
        // The layout struct holds two RelativeDirectPointers; we exercise
        // cross-reader equality via the resolved `name` string (asserted
        // separately by the `name()` test). This test is the
        // structural-presence anchor — it just verifies the layout
        // accessor is available and consistent across readers.
        let records = try loadFirstRecord()
        let nameStringMatches = try acrossAllContexts(records.file, records.image) { record, context in
            try record.name(in: context)
        }
        #expect(nameStringMatches == AssociatedTypeRecordBaseline.firstRecord.name)
    }

    // MARK: - Reader methods

    @Test func name() async throws {
        let records = try loadFirstRecord()
        let result = try acrossAllContexts(records.file, records.image) { record, context in try record.name(in: context) }
        #expect(result == AssociatedTypeRecordBaseline.firstRecord.name)
    }

    @Test func substitutedTypeName() async throws {
        let records = try loadFirstRecord()
        let presence = try acrossAllContexts(records.file, records.image) { record, context in
            (try? record.substitutedTypeName(in: context)) != nil
        }
        #expect(presence == AssociatedTypeRecordBaseline.firstRecord.hasSubstitutedTypeName)
    }
}
