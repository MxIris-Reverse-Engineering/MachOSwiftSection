import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `OverrideTableHeader`.
///
/// The Suite picks the override-table header from `Classes.SubclassTest`
/// and asserts cross-reader equality on `offset` and `numEntries`.
@Suite
@FixtureSuite
final class OverrideTableHeaderTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadSubclassOverrideHeaders() throws -> (file: OverrideTableHeader, image: OverrideTableHeader) {
        let fileDescriptor = try BaselineFixturePicker.class_SubclassTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_SubclassTest(in: machOImage)
        let fileClass = try Class(descriptor: fileDescriptor, in: fileContext)
        let imageClass = try Class(descriptor: imageDescriptor, in: imageContext)
        let fileHeader = try required(fileClass.overrideTableHeader)
        let imageHeader = try required(imageClass.overrideTableHeader)
        return (file: fileHeader, image: imageHeader)
    }

    @Test func offset() async throws {
        let headers = try loadSubclassOverrideHeaders()
        let result = try acrossAllReaders(headers.file, headers.image) { $0.offset }
        #expect(result == OverrideTableHeaderBaseline.subclassTest.offset)
    }

    @Test func layout() async throws {
        let headers = try loadSubclassOverrideHeaders()
        let numEntries = try acrossAllReaders(headers.file, headers.image) { $0.layout.numEntries }
        #expect(numEntries == OverrideTableHeaderBaseline.subclassTest.layoutNumEntries)
    }
}
