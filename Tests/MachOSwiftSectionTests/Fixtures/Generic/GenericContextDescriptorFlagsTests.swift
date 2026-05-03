import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `GenericContextDescriptorFlags`.
///
/// `GenericContextDescriptorFlags` is the 16-bit `OptionSet` packed into
/// the leading `flags` field of every `GenericContextDescriptorHeader`.
/// The Suite exercises each option bit (`hasTypePacks`,
/// `hasConditionalInvertedProtocols`, `hasValues`) plus the
/// `init(rawValue:)` round-trip against synthetic raw values from the
/// baseline.
@Suite
final class GenericContextDescriptorFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericContextDescriptorFlags"
    static var registeredTestMethodNames: Set<String> {
        GenericContextDescriptorFlagsBaseline.registeredTestMethodNames
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        let allFlags = GenericContextDescriptorFlags(
            rawValue: GenericContextDescriptorFlagsBaseline.all.rawValue
        )
        #expect(allFlags.rawValue == GenericContextDescriptorFlagsBaseline.all.rawValue)
    }

    @Test func rawValue() async throws {
        let typePacks = GenericContextDescriptorFlags(
            rawValue: GenericContextDescriptorFlagsBaseline.typePacksOnly.rawValue
        )
        #expect(typePacks.rawValue == GenericContextDescriptorFlagsBaseline.typePacksOnly.rawValue)
    }

    @Test func hasTypePacks() async throws {
        // Static OptionSet member carries its canonical bit pattern.
        #expect(
            GenericContextDescriptorFlags.hasTypePacks.rawValue
                == GenericContextDescriptorFlagsBaseline.typePacksOnly.rawValue
        )

        let none = GenericContextDescriptorFlags(rawValue: GenericContextDescriptorFlagsBaseline.none.rawValue)
        #expect(none.contains(.hasTypePacks) == GenericContextDescriptorFlagsBaseline.none.hasTypePacks)

        let typePacksOnly = GenericContextDescriptorFlags(rawValue: GenericContextDescriptorFlagsBaseline.typePacksOnly.rawValue)
        #expect(typePacksOnly.contains(.hasTypePacks) == GenericContextDescriptorFlagsBaseline.typePacksOnly.hasTypePacks)

        let all = GenericContextDescriptorFlags(rawValue: GenericContextDescriptorFlagsBaseline.all.rawValue)
        #expect(all.contains(.hasTypePacks) == GenericContextDescriptorFlagsBaseline.all.hasTypePacks)
    }

    @Test func hasConditionalInvertedProtocols() async throws {
        #expect(
            GenericContextDescriptorFlags.hasConditionalInvertedProtocols.rawValue
                == GenericContextDescriptorFlagsBaseline.conditionalOnly.rawValue
        )

        let conditionalOnly = GenericContextDescriptorFlags(
            rawValue: GenericContextDescriptorFlagsBaseline.conditionalOnly.rawValue
        )
        #expect(
            conditionalOnly.contains(.hasConditionalInvertedProtocols)
                == GenericContextDescriptorFlagsBaseline.conditionalOnly.hasConditionalInvertedProtocols
        )

        let none = GenericContextDescriptorFlags(rawValue: GenericContextDescriptorFlagsBaseline.none.rawValue)
        #expect(
            none.contains(.hasConditionalInvertedProtocols)
                == GenericContextDescriptorFlagsBaseline.none.hasConditionalInvertedProtocols
        )
    }

    @Test func hasValues() async throws {
        #expect(
            GenericContextDescriptorFlags.hasValues.rawValue
                == GenericContextDescriptorFlagsBaseline.valuesOnly.rawValue
        )

        let valuesOnly = GenericContextDescriptorFlags(rawValue: GenericContextDescriptorFlagsBaseline.valuesOnly.rawValue)
        #expect(valuesOnly.contains(.hasValues) == GenericContextDescriptorFlagsBaseline.valuesOnly.hasValues)

        let all = GenericContextDescriptorFlags(rawValue: GenericContextDescriptorFlagsBaseline.all.rawValue)
        #expect(all.contains(.hasValues) == GenericContextDescriptorFlagsBaseline.all.hasValues)
    }
}
