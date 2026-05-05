import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ProtocolRecord`.
///
/// `ProtocolRecord` is the one-pointer entry stored in the
/// `__swift5_protos` section. We pick the first record from the fixture
/// and verify its offset and resolved descriptor offset/name.
@Suite
final class ProtocolRecordTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ProtocolRecord"
    static var registeredTestMethodNames: Set<String> {
        ProtocolRecordBaseline.registeredTestMethodNames
    }

    private func loadFirstRecords() throws -> (file: ProtocolRecord, image: ProtocolRecord) {
        let file = try BaselineFixturePicker.protocolRecord_first(in: machOFile)
        let image = try BaselineFixturePicker.protocolRecord_first(in: machOImage)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let (file, image) = try loadFirstRecords()
        let result = try acrossAllReaders(
            file: { file.offset },
            image: { image.offset }
        )
        #expect(result == ProtocolRecordBaseline.firstRecord.offset)
    }

    @Test func layout() async throws {
        let (file, image) = try loadFirstRecords()
        // The layout's `protocol` is a relative-pointer pair; we exercise
        // its presence by resolving and comparing the descriptor offset.
        let resolvedFile = try required(file.protocolDescriptor(in: machOFile))
        let resolvedImage = try required(image.protocolDescriptor(in: machOImage))
        #expect(resolvedFile.offset == ProtocolRecordBaseline.firstRecord.resolvedDescriptorOffset)
        #expect(resolvedImage.offset == ProtocolRecordBaseline.firstRecord.resolvedDescriptorOffset)
    }

    @Test func protocolDescriptor() async throws {
        let (file, image) = try loadFirstRecords()
        let fileResolved = try required(file.protocolDescriptor(in: machOFile))
        let imageResolved = try required(image.protocolDescriptor(in: machOImage))
        #expect(fileResolved.offset == ProtocolRecordBaseline.firstRecord.resolvedDescriptorOffset)
        #expect(imageResolved.offset == ProtocolRecordBaseline.firstRecord.resolvedDescriptorOffset)

        // ReadingContext overload also exercised.
        let imageContextResolved = try required(image.protocolDescriptor(in: imageContext))
        #expect(imageContextResolved.offset == ProtocolRecordBaseline.firstRecord.resolvedDescriptorOffset)

        // Verify the resolved name is the deterministic baseline string.
        let resolvedName = try fileResolved.name(in: machOFile)
        #expect(resolvedName == ProtocolRecordBaseline.firstRecord.resolvedDescriptorName)
    }
}
