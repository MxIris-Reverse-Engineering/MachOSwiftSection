import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `MetadataSourceRecord`.
///
/// Both records of the fixture's two-source capture descriptor. Unusually for
/// this library both mangled payloads are pinned as literals, because both
/// are plain ASCII and together they show what the type is actually for: the
/// entries say the closure's two generic parameters (`x`, `q_`) are recovered
/// from closure bindings 0 and 1 (`B0`, `B1`). That second string is written
/// in the metadata source grammar, not in Swift's type mangling, and this
/// library deliberately reports it unparsed.
@Suite
final class MetadataSourceRecordTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MetadataSourceRecord"
    static var registeredTestMethodNames: Set<String> {
        MetadataSourceRecordBaseline.registeredTestMethodNames
    }

    private struct Carrier {
        let index: Int
        let file: MetadataSourceRecord
        let image: MetadataSourceRecord
        let expected: MetadataSourceRecordBaseline.Entry
    }

    private func allCarriers() throws -> [Carrier] {
        let fileRecords = try CaptureFixtureDescriptors(in: machOFile).withMultipleMetadataSources.metadataSourceRecords(in: machOFile)
        let imageRecords = try CaptureFixtureDescriptors(in: machOImage).withMultipleMetadataSources.metadataSourceRecords(in: machOImage)
        return zip(fileRecords, imageRecords).enumerated().map { index, pair in
            Carrier(
                index: index,
                file: pair.0,
                image: pair.1,
                expected: MetadataSourceRecordBaseline.records[index]
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
            let relativeOffsets = try acrossAllReaders(
                file: { [carrier.file.layout.mangledTypeName.relativeOffset, carrier.file.layout.mangledMetadataSource.relativeOffset] },
                image: { [carrier.image.layout.mangledTypeName.relativeOffset, carrier.image.layout.mangledMetadataSource.relativeOffset] }
            )
            #expect(relativeOffsets.allSatisfy { $0 != 0 }, "record \(carrier.index)")
        }
        #expect(MemoryLayout<MetadataSourceRecord.Layout>.size == 8)
    }

    @Test func mangledTypeName() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { try carrier.file.mangledTypeName(in: machOFile).rawString },
                image: { try carrier.image.mangledTypeName(in: machOImage).rawString },
                inProcess: { try carrier.image.asPointerWrapper(in: self.machOImage).mangledTypeName().rawString }
            )
            #expect(result == carrier.expected.mangledTypeName, "record \(carrier.index)")

            let fromContext = try acrossAllContexts(
                file: { try carrier.file.mangledTypeName(in: fileContext).rawString },
                image: { try carrier.image.mangledTypeName(in: imageContext).rawString }
            )
            #expect(fromContext == carrier.expected.mangledTypeName, "record \(carrier.index)")
        }
    }

    @Test func mangledMetadataSource() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { try carrier.file.mangledMetadataSource(in: machOFile).rawString },
                image: { try carrier.image.mangledMetadataSource(in: machOImage).rawString },
                inProcess: { try carrier.image.asPointerWrapper(in: self.machOImage).mangledMetadataSource().rawString }
            )
            #expect(result == carrier.expected.mangledMetadataSource, "record \(carrier.index)")

            let fromContext = try acrossAllContexts(
                file: { try carrier.file.mangledMetadataSource(in: fileContext).rawString },
                image: { try carrier.image.mangledMetadataSource(in: imageContext).rawString }
            )
            #expect(fromContext == carrier.expected.mangledMetadataSource, "record \(carrier.index)")
        }

        // The two entries are distinct bindings; if they collapsed to the
        // same recipe the fixture would no longer show the index varying.
        let recipes = try allCarriers().map { try $0.file.mangledMetadataSource(in: machOFile).rawString }
        #expect(Set(recipes).count == recipes.count)
    }
}
