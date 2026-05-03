import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `GenericRequirementFlags`.
///
/// `GenericRequirementFlags` packs a `GenericRequirementKind` into the
/// lowest 5 bits plus three orthogonal option bits (`isPackRequirement`,
/// `hasKeyArgument`, `isValueRequirement`). The Suite exercises each
/// branch against synthetic raw values from the baseline.
@Suite
final class GenericRequirementFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericRequirementFlags"
    static var registeredTestMethodNames: Set<String> {
        GenericRequirementFlagsBaseline.registeredTestMethodNames
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        let flags = GenericRequirementFlags(rawValue: GenericRequirementFlagsBaseline.protocolWithKey.rawValue)
        #expect(flags.rawValue == GenericRequirementFlagsBaseline.protocolWithKey.rawValue)
    }

    @Test func rawValue() async throws {
        let layoutOnly = GenericRequirementFlags(rawValue: GenericRequirementFlagsBaseline.layoutOnly.rawValue)
        #expect(layoutOnly.rawValue == GenericRequirementFlagsBaseline.layoutOnly.rawValue)
    }

    @Test func kind() async throws {
        let protocolDefault = GenericRequirementFlags(rawValue: GenericRequirementFlagsBaseline.protocolDefault.rawValue)
        #expect(protocolDefault.kind.rawValue == GenericRequirementFlagsBaseline.protocolDefault.kindRawValue)

        let sameType = GenericRequirementFlags(rawValue: GenericRequirementFlagsBaseline.sameType.rawValue)
        #expect(sameType.kind.rawValue == GenericRequirementFlagsBaseline.sameType.kindRawValue)

        let layoutOnly = GenericRequirementFlags(rawValue: GenericRequirementFlagsBaseline.layoutOnly.rawValue)
        #expect(layoutOnly.kind.rawValue == GenericRequirementFlagsBaseline.layoutOnly.kindRawValue)

        let packWithKey = GenericRequirementFlags(rawValue: GenericRequirementFlagsBaseline.packWithKey.rawValue)
        #expect(packWithKey.kind.rawValue == GenericRequirementFlagsBaseline.packWithKey.kindRawValue)
    }

    @Test func isPackRequirement() async throws {
        // Static OptionSet member carries its canonical bit pattern (0x20).
        #expect(GenericRequirementFlags.isPackRequirement.rawValue == 0x20)

        let packWithKey = GenericRequirementFlags(rawValue: GenericRequirementFlagsBaseline.packWithKey.rawValue)
        #expect(packWithKey.contains(.isPackRequirement) == GenericRequirementFlagsBaseline.packWithKey.isPackRequirement)

        let protocolDefault = GenericRequirementFlags(rawValue: GenericRequirementFlagsBaseline.protocolDefault.rawValue)
        #expect(protocolDefault.contains(.isPackRequirement) == GenericRequirementFlagsBaseline.protocolDefault.isPackRequirement)
    }

    @Test func hasKeyArgument() async throws {
        // Static OptionSet member carries its canonical bit pattern (0x80).
        #expect(GenericRequirementFlags.hasKeyArgument.rawValue == 0x80)

        let protocolWithKey = GenericRequirementFlags(rawValue: GenericRequirementFlagsBaseline.protocolWithKey.rawValue)
        #expect(protocolWithKey.contains(.hasKeyArgument) == GenericRequirementFlagsBaseline.protocolWithKey.hasKeyArgument)

        let protocolDefault = GenericRequirementFlags(rawValue: GenericRequirementFlagsBaseline.protocolDefault.rawValue)
        #expect(protocolDefault.contains(.hasKeyArgument) == GenericRequirementFlagsBaseline.protocolDefault.hasKeyArgument)
    }

    @Test func isValueRequirement() async throws {
        // Static OptionSet member carries its canonical bit pattern (0x100).
        #expect(GenericRequirementFlags.isValueRequirement.rawValue == 0x100)

        let valueRequirement = GenericRequirementFlags(rawValue: GenericRequirementFlagsBaseline.valueRequirement.rawValue)
        #expect(valueRequirement.contains(.isValueRequirement) == GenericRequirementFlagsBaseline.valueRequirement.isValueRequirement)

        let protocolDefault = GenericRequirementFlags(rawValue: GenericRequirementFlagsBaseline.protocolDefault.rawValue)
        #expect(protocolDefault.contains(.isValueRequirement) == GenericRequirementFlagsBaseline.protocolDefault.isValueRequirement)
    }
}
