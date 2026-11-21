import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `VTableDescriptorHeader`.
///
/// The Suite picks the vtable header from `Classes.ClassTest` and asserts
/// cross-reader equality on `offset`, `vTableOffset`, and `vTableSize`.
@Suite
@FixtureSuite
final class VTableDescriptorHeaderTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadClassTestVTableHeaders() throws -> (file: VTableDescriptorHeader, image: VTableDescriptorHeader) {
        let fileDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let fileClass = try Class(descriptor: fileDescriptor, in: fileContext)
        let imageClass = try Class(descriptor: imageDescriptor, in: imageContext)
        let fileHeader = try required(fileClass.vTableDescriptorHeader)
        let imageHeader = try required(imageClass.vTableDescriptorHeader)
        return (file: fileHeader, image: imageHeader)
    }

    @Test func offset() async throws {
        let headers = try loadClassTestVTableHeaders()
        let result = try acrossAllReaders(headers.file, headers.image) { $0.offset }
        #expect(result == VTableDescriptorHeaderBaseline.classTest.offset)
    }

    @Test func layout() async throws {
        let headers = try loadClassTestVTableHeaders()
        let vTableOffset = try acrossAllReaders(headers.file, headers.image) { $0.layout.vTableOffset }
        let vTableSize = try acrossAllReaders(headers.file, headers.image) { $0.layout.vTableSize }
        #expect(vTableOffset == VTableDescriptorHeaderBaseline.classTest.layoutVTableOffset)
        #expect(vTableSize == VTableDescriptorHeaderBaseline.classTest.layoutVTableSize)
    }
}
