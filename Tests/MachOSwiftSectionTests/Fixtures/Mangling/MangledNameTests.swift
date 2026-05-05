import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `MangledName`.
///
/// Carrier: `mangledTypeName` of the multi-payload-enum descriptor for
/// `Enums.MultiPayloadEnumTests`. Asserts cross-reader equality on
/// `isEmpty`, `rawString`, and `lookupElements.count` (the underlying
/// element-array isn't deep-compared because it carries reader-
/// specific offset values).
@Suite
final class MangledNameTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MangledName"
    static var registeredTestMethodNames: Set<String> {
        MangledNameBaseline.registeredTestMethodNames
    }

    private func loadMangledNames() throws -> (file: MangledName, image: MangledName) {
        let fileDescriptor = try BaselineFixturePicker.multiPayloadEnumDescriptor_MultiPayloadEnumTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.multiPayloadEnumDescriptor_MultiPayloadEnumTest(in: machOImage)
        let file = try fileDescriptor.mangledTypeName(in: machOFile)
        let image = try imageDescriptor.mangledTypeName(in: machOImage)
        return (file: file, image: image)
    }

    @Test func isEmpty() async throws {
        let names = try loadMangledNames()
        let result = try acrossAllReaders(
            file: { names.file.isEmpty },
            image: { names.image.isEmpty }
        )
        #expect(result == MangledNameBaseline.multiPayloadEnumName.isEmpty)
    }

    @Test func rawString() async throws {
        let names = try loadMangledNames()
        let result = try acrossAllReaders(
            file: { names.file.rawString },
            image: { names.image.rawString }
        )
        #expect(result == MangledNameBaseline.multiPayloadEnumName.rawString)
    }

    @Test func symbolString() async throws {
        let names = try loadMangledNames()
        // symbolString applies prefix-insertion if the raw string isn't
        // already a Swift symbol; the result is reader-independent.
        let result = try acrossAllReaders(
            file: { names.file.symbolString },
            image: { names.image.symbolString }
        )
        #expect(!result.isEmpty)
    }

    @Test func typeString() async throws {
        let names = try loadMangledNames()
        // typeString strips the prefix if present; reader-independent.
        let result = try acrossAllReaders(
            file: { names.file.typeString },
            image: { names.image.typeString }
        )
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
        // the MachO-based overloads against the descriptor's
        // mangledTypeName offset.
        let fileDescriptor = try BaselineFixturePicker.multiPayloadEnumDescriptor_MultiPayloadEnumTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.multiPayloadEnumDescriptor_MultiPayloadEnumTest(in: machOImage)
        let mangledNameOffset = fileDescriptor.offset(of: \.mangledTypeName)
        let imageOffset = imageDescriptor.offset(of: \.mangledTypeName)
        let relativeFile = fileDescriptor.layout.mangledTypeName.relativeOffset
        let relativeImage = imageDescriptor.layout.mangledTypeName.relativeOffset

        let fileResolved = try MangledName.resolve(from: mangledNameOffset + Int(relativeFile), in: machOFile)
        let imageResolved = try MangledName.resolve(from: imageOffset + Int(relativeImage), in: machOImage)
        #expect(fileResolved.lookupElements.count == MangledNameBaseline.multiPayloadEnumName.lookupElementsCount)
        #expect(imageResolved.lookupElements.count == MangledNameBaseline.multiPayloadEnumName.lookupElementsCount)
    }
}
