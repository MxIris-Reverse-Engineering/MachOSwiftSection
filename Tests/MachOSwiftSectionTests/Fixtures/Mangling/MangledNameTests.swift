import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `MangledName`.
///
/// Carrier: `mangledTypeName` of the multi-payload-enum descriptor for
/// `Enums.MultiPayloadEnumTests`. Asserts cross-reader equality on
/// `isEmpty`, `rawString`, and `lookupElements.count` (the underlying
/// element-array isn't deep-compared because it carries reader-
/// specific offset values).
@Suite
@FixtureSuite
final class MangledNameTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadMangledNames() throws -> (file: MangledName, image: MangledName) {
        let fileDescriptor = try BaselineFixturePicker.multiPayloadEnumDescriptor_MultiPayloadEnumTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.multiPayloadEnumDescriptor_MultiPayloadEnumTest(in: machOImage)
        let file = try fileDescriptor.mangledTypeName(in: fileContext)
        let image = try imageDescriptor.mangledTypeName(in: imageContext)
        return (file: file, image: image)
    }

    @Test func isEmpty() async throws {
        let names = try loadMangledNames()
        let result = try acrossAllReaders(names.file, names.image) { $0.isEmpty }
        #expect(result == MangledNameBaseline.multiPayloadEnumName.isEmpty)
    }

    @Test func rawString() async throws {
        let names = try loadMangledNames()
        let result = try acrossAllReaders(names.file, names.image) { $0.rawString }
        #expect(result == MangledNameBaseline.multiPayloadEnumName.rawString)
    }

    @Test func symbolString() async throws {
        let names = try loadMangledNames()
        // symbolString applies prefix-insertion if the raw string isn't
        // already a Swift symbol; the result is reader-independent.
        let result = try acrossAllReaders(names.file, names.image) { $0.symbolString }
        #expect(!result.isEmpty)
    }

    @Test func typeString() async throws {
        let names = try loadMangledNames()
        // typeString strips the prefix if present; reader-independent.
        let result = try acrossAllReaders(names.file, names.image) { $0.typeString }
        #expect(!result.isEmpty)
    }

    @Test func description() async throws {
        let names = try loadMangledNames()
        // The CustomStringConvertible description embeds reader-specific
        // offset values for lookup elements, so we only assert the
        // structural prefix/suffix and presence of the lookup-element
        // marker for each lookup.
        let fileDescription = names.file.description
        let imageDescription = names.image.description
        let separator = "******************************************"
        #expect(fileDescription.contains(separator))
        #expect(imageDescription.contains(separator))
    }

    @Test func resolve() async throws {
        // Static `resolve` overloads collapse to one MethodKey. Exercise
        // the ReadingContext-based overload over both readers against the
        // descriptor's mangledTypeName offset.
        let fileDescriptor = try BaselineFixturePicker.multiPayloadEnumDescriptor_MultiPayloadEnumTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.multiPayloadEnumDescriptor_MultiPayloadEnumTest(in: machOImage)
        let mangledNameOffset = fileDescriptor.offset(of: \.mangledTypeName)
        let imageOffset = imageDescriptor.offset(of: \.mangledTypeName)
        let relativeFile = fileDescriptor.layout.mangledTypeName.relativeOffset
        let relativeImage = imageDescriptor.layout.mangledTypeName.relativeOffset

        let fileResolved = try MangledName.resolve(at: mangledNameOffset + Int(relativeFile), in: fileContext)
        let imageResolved = try MangledName.resolve(at: imageOffset + Int(relativeImage), in: imageContext)
        #expect(fileResolved.lookupElements.count == MangledNameBaseline.multiPayloadEnumName.lookupElementsCount)
        #expect(imageResolved.lookupElements.count == MangledNameBaseline.multiPayloadEnumName.lookupElementsCount)
    }
}
