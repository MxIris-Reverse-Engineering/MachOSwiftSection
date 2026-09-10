import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `CaptureTypeRecord`.
///
/// One record per fixture capture descriptor — the first captured value's
/// type. The mangled names carry symbolic references, so what is pinned is
/// the record's location and the fact that the payload resolves; the payload
/// itself is only required to agree across readers.
@Suite
final class CaptureTypeRecordTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "CaptureTypeRecord"
    static var registeredTestMethodNames: Set<String> {
        CaptureTypeRecordBaseline.registeredTestMethodNames
    }

    private struct Carrier {
        let index: Int
        let file: CaptureTypeRecord
        let image: CaptureTypeRecord
        let expected: CaptureTypeRecordBaseline.Entry
    }

    private func allCarriers() throws -> [Carrier] {
        let fileDescriptors = try CaptureFixtureDescriptors(in: machOFile).all
        let imageDescriptors = try CaptureFixtureDescriptors(in: machOImage).all
        return try zip(fileDescriptors, imageDescriptors).enumerated().map { index, pair in
            Carrier(
                index: index,
                file: try pair.0.captureTypeRecords(in: machOFile)[0],
                image: try pair.1.captureTypeRecords(in: machOImage)[0],
                expected: CaptureTypeRecordBaseline.firstRecords[index]
            )
        }
    }

    @Test func offset() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { carrier.file.offset },
                image: { carrier.image.offset }
            )
            #expect(result == carrier.expected.offset, "record \(carrier.index)")
        }
    }

    @Test func layout() async throws {
        for carrier in try allCarriers() {
            let relativeOffset = try acrossAllReaders(
                file: { carrier.file.layout.mangledTypeName.relativeOffset },
                image: { carrier.image.layout.mangledTypeName.relativeOffset }
            )
            #expect(relativeOffset != 0, "record \(carrier.index)")
        }
        // A capture type record is exactly one relative pointer; the whole
        // trailing-array arithmetic in CaptureDescriptor depends on it.
        #expect(MemoryLayout<CaptureTypeRecord.Layout>.size == 4)
    }

    @Test func mangledTypeName() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { try carrier.file.mangledTypeName(in: machOFile).rawString },
                image: { try carrier.image.mangledTypeName(in: machOImage).rawString },
                inProcess: { try carrier.image.asPointerWrapper(in: self.machOImage).mangledTypeName().rawString }
            )
            #expect(!result.isEmpty == carrier.expected.hasMangledTypeName, "record \(carrier.index)")

            let fromContext = try acrossAllContexts(
                file: { try carrier.file.mangledTypeName(in: fileContext).rawString },
                image: { try carrier.image.mangledTypeName(in: imageContext).rawString }
            )
            #expect(fromContext == result, "record \(carrier.index)")
        }
    }
}
