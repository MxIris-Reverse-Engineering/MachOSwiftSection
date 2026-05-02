import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `VTableDescriptorHeader`.
///
/// The Suite picks the vtable header from `Classes.ClassTest` and asserts
/// cross-reader equality on `offset`, `vTableOffset`, and `vTableSize`.
@Suite
final class VTableDescriptorHeaderTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "VTableDescriptorHeader"
    static var registeredTestMethodNames: Set<String> {
        VTableDescriptorHeaderBaseline.registeredTestMethodNames
    }

    private func loadClassTestVTableHeaders() throws -> (file: VTableDescriptorHeader, image: VTableDescriptorHeader) {
        let fileDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let fileClass = try Class(descriptor: fileDescriptor, in: machOFile)
        let imageClass = try Class(descriptor: imageDescriptor, in: machOImage)
        let fileHeader = try required(fileClass.vTableDescriptorHeader)
        let imageHeader = try required(imageClass.vTableDescriptorHeader)
        return (file: fileHeader, image: imageHeader)
    }

    @Test func offset() async throws {
        let headers = try loadClassTestVTableHeaders()
        let result = try acrossAllReaders(
            file: { headers.file.offset },
            image: { headers.image.offset }
        )
        #expect(result == VTableDescriptorHeaderBaseline.classTest.offset)
    }

    @Test func layout() async throws {
        let headers = try loadClassTestVTableHeaders()
        let vTableOffset = try acrossAllReaders(
            file: { headers.file.layout.vTableOffset },
            image: { headers.image.layout.vTableOffset }
        )
        let vTableSize = try acrossAllReaders(
            file: { headers.file.layout.vTableSize },
            image: { headers.image.layout.vTableSize }
        )
        #expect(vTableOffset == VTableDescriptorHeaderBaseline.classTest.layoutVTableOffset)
        #expect(vTableSize == VTableDescriptorHeaderBaseline.classTest.layoutVTableSize)
    }
}
