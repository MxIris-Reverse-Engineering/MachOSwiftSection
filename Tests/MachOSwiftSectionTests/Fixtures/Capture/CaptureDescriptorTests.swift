import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `CaptureDescriptor`.
///
/// The three carriers are picked by shape rather than by position, so the
/// two trailing arrays are covered at length zero, one and many: a
/// non-generic closure's context, a closure in a one-parameter generic
/// function, and one in a two-parameter generic function.
@Suite
final class CaptureDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "CaptureDescriptor"
    static var registeredTestMethodNames: Set<String> {
        CaptureDescriptorBaseline.registeredTestMethodNames
    }

    private struct Carrier {
        let label: String
        let file: CaptureDescriptor
        let image: CaptureDescriptor
        let expected: CaptureDescriptorBaseline.Entry
    }

    private func allCarriers() throws -> [Carrier] {
        let fileDescriptors = try CaptureFixtureDescriptors(in: machOFile)
        let imageDescriptors = try CaptureFixtureDescriptors(in: machOImage)
        return [
            Carrier(
                label: "withoutMetadataSources",
                file: fileDescriptors.withoutMetadataSources,
                image: imageDescriptors.withoutMetadataSources,
                expected: CaptureDescriptorBaseline.withoutMetadataSources
            ),
            Carrier(
                label: "withSingleMetadataSource",
                file: fileDescriptors.withSingleMetadataSource,
                image: imageDescriptors.withSingleMetadataSource,
                expected: CaptureDescriptorBaseline.withSingleMetadataSource
            ),
            Carrier(
                label: "withMultipleMetadataSources",
                file: fileDescriptors.withMultipleMetadataSources,
                image: imageDescriptors.withMultipleMetadataSources,
                expected: CaptureDescriptorBaseline.withMultipleMetadataSources
            ),
        ]
    }

    @Test func offset() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { carrier.file.offset },
                image: { carrier.image.offset }
            )
            #expect(result == carrier.expected.offset, "\(carrier.label)")
        }
    }

    @Test func layout() async throws {
        for carrier in try allCarriers() {
            let counts = try acrossAllReaders(
                file: { [carrier.file.layout.numberOfCaptureTypes, carrier.file.layout.numberOfMetadataSources, carrier.file.layout.numberOfBindings] },
                image: { [carrier.image.layout.numberOfCaptureTypes, carrier.image.layout.numberOfMetadataSources, carrier.image.layout.numberOfBindings] }
            )
            #expect(counts.map(Int.init) == [carrier.expected.numberOfCaptureTypes, carrier.expected.numberOfMetadataSources, carrier.expected.numberOfBindings], "\(carrier.label)")
        }
        #expect(MemoryLayout<CaptureDescriptor.Layout>.size == 12)

        // Zero, one and many: if the fixture ever stopped carrying all three
        // the trailing-array arithmetic would only be tested in one shape.
        #expect(Set(try allCarriers().map(\.file.layout.numberOfMetadataSources)) == [0, 1, 2])
    }

    /// The section is walked by size, so a wrong `actualSize` would desync
    /// every later descriptor rather than fail locally. The walk over the
    /// whole section is the real assertion here.
    @Test func actualSize() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { carrier.file.actualSize },
                image: { carrier.image.actualSize }
            )
            #expect(result == carrier.expected.actualSize, "\(carrier.label)")
            #expect(
                result == MemoryLayout<CaptureDescriptor.Layout>.size
                    + carrier.expected.numberOfCaptureTypes * MemoryLayout<CaptureTypeRecord.Layout>.size
                    + carrier.expected.numberOfMetadataSources * MemoryLayout<MetadataSourceRecord.Layout>.size,
                "\(carrier.label)"
            )
        }

        let descriptors = try BaselineFixturePicker.captureDescriptors(in: machOFile)
        #expect(descriptors.count == CaptureDescriptorBaseline.descriptorCount)
        for (earlier, later) in zip(descriptors, descriptors.dropFirst()) {
            #expect(later.offset - earlier.offset == earlier.actualSize)
        }
    }

    @Test func captureTypeRecordsOffset() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { carrier.file.captureTypeRecordsOffset },
                image: { carrier.image.captureTypeRecordsOffset }
            )
            #expect(result == carrier.expected.captureTypeRecordsOffset, "\(carrier.label)")
        }
    }

    @Test func metadataSourceRecordsOffset() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { carrier.file.metadataSourceRecordsOffset },
                image: { carrier.image.metadataSourceRecordsOffset }
            )
            #expect(result == carrier.expected.metadataSourceRecordsOffset, "\(carrier.label)")
        }
    }

    @Test func captureTypeRecords() async throws {
        for carrier in try allCarriers() {
            let offsets = try acrossAllReaders(
                file: { try carrier.file.captureTypeRecords(in: machOFile).map(\.offset) },
                image: { try carrier.image.captureTypeRecords(in: machOImage).map(\.offset) }
            )
            #expect(offsets.count == carrier.expected.numberOfCaptureTypes, "\(carrier.label)")
            #expect(offsets.first == carrier.expected.captureTypeRecordsOffset, "\(carrier.label)")

            let fromContext = try acrossAllContexts(
                file: { try carrier.file.captureTypeRecords(in: fileContext).map(\.offset) },
                image: { try carrier.image.captureTypeRecords(in: imageContext).map(\.offset) }
            )
            #expect(fromContext == offsets, "\(carrier.label)")

            // The in-process leg reads through a pointer, so its offsets are
            // pointers; only the count is comparable directly.
            let inProcess = try carrier.image.asPointerWrapper(in: machOImage).captureTypeRecords()
            #expect(inProcess.count == carrier.expected.numberOfCaptureTypes, "\(carrier.label)")
        }
    }

    @Test func metadataSourceRecords() async throws {
        for carrier in try allCarriers() {
            let sources = try acrossAllReaders(
                file: { try carrier.file.metadataSourceRecords(in: machOFile).map { try $0.mangledMetadataSource(in: machOFile).rawString } },
                image: { try carrier.image.metadataSourceRecords(in: machOImage).map { try $0.mangledMetadataSource(in: machOImage).rawString } }
            )
            #expect(sources == carrier.expected.mangledMetadataSources, "\(carrier.label)")

            let fromContext = try acrossAllContexts(
                file: { try carrier.file.metadataSourceRecords(in: fileContext).map { try $0.mangledMetadataSource(in: fileContext).rawString } },
                image: { try carrier.image.metadataSourceRecords(in: imageContext).map { try $0.mangledMetadataSource(in: imageContext).rawString } }
            )
            #expect(fromContext == carrier.expected.mangledMetadataSources, "\(carrier.label)")

            let inProcess = try carrier.image.asPointerWrapper(in: machOImage).metadataSourceRecords()
            #expect(inProcess.count == carrier.expected.numberOfMetadataSources, "\(carrier.label)")
        }
    }
}
