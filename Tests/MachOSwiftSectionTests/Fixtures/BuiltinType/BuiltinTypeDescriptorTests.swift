import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `BuiltinTypeDescriptor`.
///
/// Picker: the first descriptor in the `__swift5_builtin` section of
/// SymbolTestsCore. The fixture's `BuiltinTypeFields` namespace causes
/// the compiler to emit one descriptor per primitive backing type used
/// in stored fields. The Suite asserts cross-reader equality of the
/// layout fields and the typeName resolution.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
@FixtureSuite
final class BuiltinTypeDescriptorTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadDescriptors() throws -> (file: BuiltinTypeDescriptor, image: BuiltinTypeDescriptor) {
        let file = try BaselineFixturePicker.builtinTypeDescriptor_first(in: machOFile)
        let image = try BaselineFixturePicker.builtinTypeDescriptor_first(in: machOImage)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let descriptors = try loadDescriptors()
        let result = try acrossAllReaders(descriptors.file, descriptors.image) { $0.offset }
        #expect(result == BuiltinTypeDescriptorBaseline.firstBuiltin.descriptorOffset)
    }

    @Test func layout() async throws {
        let descriptors = try loadDescriptors()
        let size = try acrossAllReaders(descriptors.file, descriptors.image) { $0.layout.size }
        let stride = try acrossAllReaders(descriptors.file, descriptors.image) { $0.layout.stride }
        let alignmentAndFlags = try acrossAllReaders(descriptors.file, descriptors.image) { $0.layout.alignmentAndFlags }
        let numExtraInhabitants = try acrossAllReaders(descriptors.file, descriptors.image) { $0.layout.numExtraInhabitants }

        #expect(size == BuiltinTypeDescriptorBaseline.firstBuiltin.size)
        #expect(stride == BuiltinTypeDescriptorBaseline.firstBuiltin.stride)
        #expect(alignmentAndFlags == BuiltinTypeDescriptorBaseline.firstBuiltin.alignmentAndFlags)
        #expect(numExtraInhabitants == BuiltinTypeDescriptorBaseline.firstBuiltin.numExtraInhabitants)
    }

    @Test func alignment() async throws {
        let descriptors = try loadDescriptors()
        let result = try acrossAllReaders(descriptors.file, descriptors.image) { $0.alignment }
        #expect(result == BuiltinTypeDescriptorBaseline.firstBuiltin.alignment)
    }

    @Test func isBitwiseTakable() async throws {
        let descriptors = try loadDescriptors()
        let result = try acrossAllReaders(descriptors.file, descriptors.image) { $0.isBitwiseTakable }
        #expect(result == BuiltinTypeDescriptorBaseline.firstBuiltin.isBitwiseTakable)
    }

    @Test func hasMangledName() async throws {
        let descriptors = try loadDescriptors()
        let result = try acrossAllReaders(descriptors.file, descriptors.image) { $0.hasMangledName }
        #expect(result == BuiltinTypeDescriptorBaseline.firstBuiltin.hasMangledName)
    }

    @Test func typeName() async throws {
        let descriptors = try loadDescriptors()
        // typeName resolution returns an Optional<MangledName>. The
        // baseline records whether the mangled-name pointer is non-null
        // (`hasMangledName`); the resolved name itself isn't byte-stable
        // across builds, so we only assert non-nil presence.
        let viaFile = try descriptors.file.typeName(in: fileContext)
        let viaImage = try descriptors.image.typeName(in: imageContext)
        if BuiltinTypeDescriptorBaseline.firstBuiltin.hasMangledName {
            #expect(viaFile != nil)
            #expect(viaImage != nil)
        }
    }
}
