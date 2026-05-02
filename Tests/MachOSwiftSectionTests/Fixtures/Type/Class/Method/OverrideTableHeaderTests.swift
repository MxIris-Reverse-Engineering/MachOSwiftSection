import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `OverrideTableHeader`.
///
/// The Suite picks the override-table header from `Classes.SubclassTest`
/// and asserts cross-reader equality on `offset` and `numEntries`.
@Suite
final class OverrideTableHeaderTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "OverrideTableHeader"
    static var registeredTestMethodNames: Set<String> {
        OverrideTableHeaderBaseline.registeredTestMethodNames
    }

    private func loadSubclassOverrideHeaders() throws -> (file: OverrideTableHeader, image: OverrideTableHeader) {
        let fileDescriptor = try BaselineFixturePicker.class_SubclassTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_SubclassTest(in: machOImage)
        let fileClass = try Class(descriptor: fileDescriptor, in: machOFile)
        let imageClass = try Class(descriptor: imageDescriptor, in: machOImage)
        let fileHeader = try required(fileClass.overrideTableHeader)
        let imageHeader = try required(imageClass.overrideTableHeader)
        return (file: fileHeader, image: imageHeader)
    }

    @Test func offset() async throws {
        let headers = try loadSubclassOverrideHeaders()
        let result = try acrossAllReaders(
            file: { headers.file.offset },
            image: { headers.image.offset }
        )
        #expect(result == OverrideTableHeaderBaseline.subclassTest.offset)
    }

    @Test func layout() async throws {
        let headers = try loadSubclassOverrideHeaders()
        let numEntries = try acrossAllReaders(
            file: { headers.file.layout.numEntries },
            image: { headers.image.layout.numEntries }
        )
        #expect(numEntries == OverrideTableHeaderBaseline.subclassTest.layoutNumEntries)
    }
}
