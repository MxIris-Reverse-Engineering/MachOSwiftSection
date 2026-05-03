import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `FieldRecordFlags`.
///
/// `FieldRecordFlags` is a 32-bit `OptionSet` carrying three orthogonal
/// option bits (`isIndirectCase`, `isVariadic`, `isArtificial`). The Suite
/// exercises each membership predicate against synthetic raw values
/// embedded in the baseline.
@Suite
final class FieldRecordFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "FieldRecordFlags"
    static var registeredTestMethodNames: Set<String> {
        FieldRecordFlagsBaseline.registeredTestMethodNames
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        let flags = FieldRecordFlags(rawValue: FieldRecordFlagsBaseline.allBits.rawValue)
        #expect(flags.rawValue == FieldRecordFlagsBaseline.allBits.rawValue)
    }

    @Test func rawValue() async throws {
        let allBits = FieldRecordFlags(rawValue: FieldRecordFlagsBaseline.allBits.rawValue)
        #expect(allBits.rawValue == FieldRecordFlagsBaseline.allBits.rawValue)
    }

    @Test func isIndirectCase() async throws {
        // Static OptionSet member carries its canonical bit pattern (0x1).
        #expect(FieldRecordFlags.isIndirectCase.rawValue == 0x1)

        let isIndirectCase = FieldRecordFlags(rawValue: FieldRecordFlagsBaseline.isIndirectCase.rawValue)
        #expect(isIndirectCase.contains(.isIndirectCase) == FieldRecordFlagsBaseline.isIndirectCase.isIndirectCase)

        let empty = FieldRecordFlags(rawValue: FieldRecordFlagsBaseline.empty.rawValue)
        #expect(empty.contains(.isIndirectCase) == FieldRecordFlagsBaseline.empty.isIndirectCase)
    }

    @Test func isVariadic() async throws {
        // Static OptionSet member carries its canonical bit pattern (0x2).
        #expect(FieldRecordFlags.isVariadic.rawValue == 0x2)

        let isVariadic = FieldRecordFlags(rawValue: FieldRecordFlagsBaseline.isVariadic.rawValue)
        #expect(isVariadic.contains(.isVariadic) == FieldRecordFlagsBaseline.isVariadic.isVariadic)

        let empty = FieldRecordFlags(rawValue: FieldRecordFlagsBaseline.empty.rawValue)
        #expect(empty.contains(.isVariadic) == FieldRecordFlagsBaseline.empty.isVariadic)
    }

    @Test func isArtificial() async throws {
        // Static OptionSet member carries its canonical bit pattern (0x4).
        #expect(FieldRecordFlags.isArtificial.rawValue == 0x4)

        let isArtificial = FieldRecordFlags(rawValue: FieldRecordFlagsBaseline.isArtificial.rawValue)
        #expect(isArtificial.contains(.isArtificial) == FieldRecordFlagsBaseline.isArtificial.isArtificial)

        let empty = FieldRecordFlags(rawValue: FieldRecordFlagsBaseline.empty.rawValue)
        #expect(empty.contains(.isArtificial) == FieldRecordFlagsBaseline.empty.isArtificial)
    }
}
