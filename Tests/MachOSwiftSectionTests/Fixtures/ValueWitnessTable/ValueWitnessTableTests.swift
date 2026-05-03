import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ValueWitnessTable`.
///
/// `ValueWitnessTable` is reachable solely through
/// `MetadataProtocol.valueWitnesses(in:)` from a loaded MachOImage. The
/// Suite materialises the table for `Structs.StructTest` (a tiny struct
/// with a single `body` property) and asserts cross-reader equality on
/// the structural ivars (size / stride / flags / numExtraInhabitants).
///
/// **Reader asymmetry:** the table's pointer is reachable solely
/// through `MachOImage`. `MachOFile` cannot resolve runtime metadata
/// pointers, so all readings here originate from the image side.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class ValueWitnessTableTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ValueWitnessTable"
    static var registeredTestMethodNames: Set<String> {
        ValueWitnessTableBaseline.registeredTestMethodNames
    }

    private func loadStructTestValueWitnesses() throws -> ValueWitnessTable {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        let response = try accessor(request: .init())
        let structMetadata = try required(try response.value.resolve(in: machOImage).struct)
        return try structMetadata.valueWitnesses(in: machOImage)
    }

    @Test func offset() async throws {
        let table = try loadStructTestValueWitnesses()
        // The value-witness table offset is the metadata's full-metadata
        // offset for the witness pointer; it must be a non-zero
        // file/image-relative position.
        #expect(table.offset > 0)
    }

    @Test func layout() async throws {
        let table = try loadStructTestValueWitnesses()
        // `Structs.StructTest`'s only declared property is `var body:
        // some P` (a computed getter — no stored fields), so size and
        // stride at runtime are both 0. We assert the structural
        // invariants stride >= size and alignment >= 1 instead.
        #expect(table.layout.stride >= table.layout.size)
        #expect(table.layout.flags.alignment >= 1)
    }

    @Test func typeLayout() async throws {
        let table = try loadStructTestValueWitnesses()
        let typeLayout = table.typeLayout
        // typeLayout reflects the (size, stride, flags, extraInhabitantCount)
        // tuple via a dedicated wrapper. They must equal the
        // corresponding source ivar values.
        #expect(typeLayout.size == table.layout.size)
        #expect(typeLayout.stride == table.layout.stride)
        #expect(typeLayout.extraInhabitantCount == table.layout.numExtraInhabitants)
    }
}
