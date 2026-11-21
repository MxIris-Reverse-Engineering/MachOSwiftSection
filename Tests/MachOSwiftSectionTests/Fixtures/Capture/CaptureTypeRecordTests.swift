import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `CaptureTypeRecord`.
///
/// One record per fixture capture descriptor — the first captured value's
/// type. The mangled names carry symbolic references, so what is pinned is
/// the record's location and the fact that the payload resolves; the payload
/// itself is only required to agree across readers.
@Suite
@FixtureSuite
final class CaptureTypeRecordTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
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
                file: try pair.0.captureTypeRecords(in: fileContext)[0],
                image: try pair.1.captureTypeRecords(in: imageContext)[0],
                expected: CaptureTypeRecordBaseline.firstRecords[index]
            )
        }
    }

    @Test func offset() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(carrier.file, carrier.image) { $0.offset }
            #expect(result == carrier.expected.offset, "record \(carrier.index)")
        }
    }

    @Test func layout() async throws {
        for carrier in try allCarriers() {
            let relativeOffset = try acrossAllReaders(carrier.file, carrier.image) { $0.layout.mangledTypeName.relativeOffset }
            #expect(relativeOffset != 0, "record \(carrier.index)")
        }
        // A capture type record is exactly one relative pointer; the whole
        // trailing-array arithmetic in CaptureDescriptor depends on it.
        #expect(MemoryLayout<CaptureTypeRecord.Layout>.size == 4)
    }

    @Test func mangledTypeName() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllContexts(
                file: { try carrier.file.mangledTypeName(in: fileContext).rawString },
                image: { try carrier.image.mangledTypeName(in: imageContext).rawString },
                inProcess: { try carrier.image.asPointerWrapper(in: self.machOImage).mangledTypeName(in: self.inProcessContext).rawString }
            )
            #expect(!result.isEmpty == carrier.expected.hasMangledTypeName, "record \(carrier.index)")
        }
    }
}
