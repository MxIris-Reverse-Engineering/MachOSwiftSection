import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

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
final class BuiltinTypeDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "BuiltinTypeDescriptor"
    static var registeredTestMethodNames: Set<String> {
        BuiltinTypeDescriptorBaseline.registeredTestMethodNames
    }

    private func loadDescriptors() throws -> (file: BuiltinTypeDescriptor, image: BuiltinTypeDescriptor) {
        let file = try BaselineFixturePicker.builtinTypeDescriptor_first(in: machOFile)
        let image = try BaselineFixturePicker.builtinTypeDescriptor_first(in: machOImage)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let descriptors = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { descriptors.file.offset },
            image: { descriptors.image.offset }
        )
        #expect(result == BuiltinTypeDescriptorBaseline.firstBuiltin.descriptorOffset)
    }

    @Test func layout() async throws {
        let descriptors = try loadDescriptors()
        let size = try acrossAllReaders(
            file: { descriptors.file.layout.size },
            image: { descriptors.image.layout.size }
        )
        let stride = try acrossAllReaders(
            file: { descriptors.file.layout.stride },
            image: { descriptors.image.layout.stride }
        )
        let alignmentAndFlags = try acrossAllReaders(
            file: { descriptors.file.layout.alignmentAndFlags },
            image: { descriptors.image.layout.alignmentAndFlags }
        )
        let numExtraInhabitants = try acrossAllReaders(
            file: { descriptors.file.layout.numExtraInhabitants },
            image: { descriptors.image.layout.numExtraInhabitants }
        )

        #expect(size == BuiltinTypeDescriptorBaseline.firstBuiltin.size)
        #expect(stride == BuiltinTypeDescriptorBaseline.firstBuiltin.stride)
        #expect(alignmentAndFlags == BuiltinTypeDescriptorBaseline.firstBuiltin.alignmentAndFlags)
        #expect(numExtraInhabitants == BuiltinTypeDescriptorBaseline.firstBuiltin.numExtraInhabitants)
    }

    @Test func alignment() async throws {
        let descriptors = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { descriptors.file.alignment },
            image: { descriptors.image.alignment }
        )
        #expect(result == BuiltinTypeDescriptorBaseline.firstBuiltin.alignment)
    }

    @Test func isBitwiseTakable() async throws {
        let descriptors = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { descriptors.file.isBitwiseTakable },
            image: { descriptors.image.isBitwiseTakable }
        )
        #expect(result == BuiltinTypeDescriptorBaseline.firstBuiltin.isBitwiseTakable)
    }

    @Test func hasMangledName() async throws {
        let descriptors = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { descriptors.file.hasMangledName },
            image: { descriptors.image.hasMangledName }
        )
        #expect(result == BuiltinTypeDescriptorBaseline.firstBuiltin.hasMangledName)
    }

    @Test func typeName() async throws {
        let descriptors = try loadDescriptors()
        // typeName resolution returns an Optional<MangledName>. The
        // baseline records whether the mangled-name pointer is non-null
        // (`hasMangledName`); the resolved name itself isn't byte-stable
        // across builds, so we only assert non-nil presence.
        let viaFile = try descriptors.file.typeName(in: machOFile)
        let viaImage = try descriptors.image.typeName(in: machOImage)
        if BuiltinTypeDescriptorBaseline.firstBuiltin.hasMangledName {
            #expect(viaFile != nil)
            #expect(viaImage != nil)
        }
        // ReadingContext path also exercised.
        let viaContext = try descriptors.image.typeName(in: imageContext)
        if BuiltinTypeDescriptorBaseline.firstBuiltin.hasMangledName {
            #expect(viaContext != nil)
        }
    }
}
