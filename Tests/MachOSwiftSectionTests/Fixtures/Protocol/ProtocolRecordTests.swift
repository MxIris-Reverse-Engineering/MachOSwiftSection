import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `ProtocolRecord`.
///
/// `ProtocolRecord` is the one-pointer entry stored in the
/// `__swift5_protos` section. We pick the first record from the fixture
/// and verify its offset and resolved descriptor offset/name.
@Suite
@FixtureSuite
final class ProtocolRecordTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadFirstRecords() throws -> (file: ProtocolRecord, image: ProtocolRecord) {
        let file = try BaselineFixturePicker.protocolRecord_first(in: machOFile)
        let image = try BaselineFixturePicker.protocolRecord_first(in: machOImage)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let (file, image) = try loadFirstRecords()
        let result = try acrossAllReaders(file, image) { $0.offset }
        #expect(result == ProtocolRecordBaseline.firstRecord.offset)
    }

    @Test func layout() async throws {
        let (file, image) = try loadFirstRecords()
        // The layout's `protocol` is a relative-pointer pair; we exercise
        // its presence by resolving and comparing the descriptor offset.
        let resolvedFile = try required(file.protocolDescriptor(in: fileContext))
        let resolvedImage = try required(image.protocolDescriptor(in: imageContext))
        #expect(resolvedFile.offset == ProtocolRecordBaseline.firstRecord.resolvedDescriptorOffset)
        #expect(resolvedImage.offset == ProtocolRecordBaseline.firstRecord.resolvedDescriptorOffset)
    }

    @Test func protocolDescriptor() async throws {
        let (file, image) = try loadFirstRecords()
        let fileResolved = try required(file.protocolDescriptor(in: fileContext))
        let imageResolved = try required(image.protocolDescriptor(in: imageContext))
        #expect(fileResolved.offset == ProtocolRecordBaseline.firstRecord.resolvedDescriptorOffset)
        #expect(imageResolved.offset == ProtocolRecordBaseline.firstRecord.resolvedDescriptorOffset)

        // Verify the resolved name is the deterministic baseline string.
        let resolvedName = try fileResolved.name(in: fileContext)
        #expect(resolvedName == ProtocolRecordBaseline.firstRecord.resolvedDescriptorName)
    }
}
