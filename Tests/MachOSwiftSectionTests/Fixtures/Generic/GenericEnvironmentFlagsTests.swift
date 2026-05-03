import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `GenericEnvironmentFlags`.
///
/// `GenericEnvironmentFlags` packs `numberOfGenericParameterLevels` into
/// the lowest 12 bits and `numberOfGenericRequirements` into the next 16
/// bits of a 32-bit raw value. The Suite exercises both decoders against
/// synthetic raw values from the baseline (no live carrier exists in
/// SymbolTestsCore — see the Generator's note).
@Suite
final class GenericEnvironmentFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericEnvironmentFlags"
    static var registeredTestMethodNames: Set<String> {
        GenericEnvironmentFlagsBaseline.registeredTestMethodNames
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        let max = GenericEnvironmentFlags(rawValue: GenericEnvironmentFlagsBaseline.maxAll.rawValue)
        #expect(max.rawValue == GenericEnvironmentFlagsBaseline.maxAll.rawValue)
    }

    @Test func rawValue() async throws {
        let zero = GenericEnvironmentFlags(rawValue: GenericEnvironmentFlagsBaseline.zero.rawValue)
        #expect(zero.rawValue == GenericEnvironmentFlagsBaseline.zero.rawValue)

        let three = GenericEnvironmentFlags(rawValue: GenericEnvironmentFlagsBaseline.threeLevelsOneRequirement.rawValue)
        #expect(three.rawValue == GenericEnvironmentFlagsBaseline.threeLevelsOneRequirement.rawValue)
    }

    @Test func numberOfGenericParameterLevels() async throws {
        let zero = GenericEnvironmentFlags(rawValue: GenericEnvironmentFlagsBaseline.zero.rawValue)
        #expect(zero.numberOfGenericParameterLevels == GenericEnvironmentFlagsBaseline.zero.numberOfGenericParameterLevels)

        let oneLevel = GenericEnvironmentFlags(rawValue: GenericEnvironmentFlagsBaseline.oneLevel.rawValue)
        #expect(oneLevel.numberOfGenericParameterLevels == GenericEnvironmentFlagsBaseline.oneLevel.numberOfGenericParameterLevels)

        let three = GenericEnvironmentFlags(rawValue: GenericEnvironmentFlagsBaseline.threeLevelsOneRequirement.rawValue)
        #expect(three.numberOfGenericParameterLevels == GenericEnvironmentFlagsBaseline.threeLevelsOneRequirement.numberOfGenericParameterLevels)

        let max = GenericEnvironmentFlags(rawValue: GenericEnvironmentFlagsBaseline.maxAll.rawValue)
        #expect(max.numberOfGenericParameterLevels == GenericEnvironmentFlagsBaseline.maxAll.numberOfGenericParameterLevels)
    }

    @Test func numberOfGenericRequirements() async throws {
        let zero = GenericEnvironmentFlags(rawValue: GenericEnvironmentFlagsBaseline.zero.rawValue)
        #expect(zero.numberOfGenericRequirements == GenericEnvironmentFlagsBaseline.zero.numberOfGenericRequirements)

        let oneLevel = GenericEnvironmentFlags(rawValue: GenericEnvironmentFlagsBaseline.oneLevel.rawValue)
        #expect(oneLevel.numberOfGenericRequirements == GenericEnvironmentFlagsBaseline.oneLevel.numberOfGenericRequirements)

        let three = GenericEnvironmentFlags(rawValue: GenericEnvironmentFlagsBaseline.threeLevelsOneRequirement.rawValue)
        #expect(three.numberOfGenericRequirements == GenericEnvironmentFlagsBaseline.threeLevelsOneRequirement.numberOfGenericRequirements)

        let max = GenericEnvironmentFlags(rawValue: GenericEnvironmentFlagsBaseline.maxAll.rawValue)
        #expect(max.numberOfGenericRequirements == GenericEnvironmentFlagsBaseline.maxAll.numberOfGenericRequirements)
    }
}
