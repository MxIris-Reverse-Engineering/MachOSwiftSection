import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `InvertibleProtocolsRequirementCount`.
///
/// `InvertibleProtocolsRequirementCount` is a thin `RawRepresentable`
/// wrapper around a `UInt16` count of invertible-protocol requirements
/// in a generic signature. The fixture has no live carrier; the Suite
/// exercises the round-trip via the synthetic raw values embedded in
/// the baseline.
@Suite
final class InvertibleProtocolsRequirementCountTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "InvertibleProtocolsRequirementCount"
    static var registeredTestMethodNames: Set<String> {
        InvertibleProtocolsRequirementCountBaseline.registeredTestMethodNames
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        let zero = InvertibleProtocolsRequirementCount(rawValue: InvertibleProtocolsRequirementCountBaseline.zero.rawValue)
        #expect(zero.rawValue == InvertibleProtocolsRequirementCountBaseline.zero.rawValue)
    }

    @Test func rawValue() async throws {
        let small = InvertibleProtocolsRequirementCount(rawValue: InvertibleProtocolsRequirementCountBaseline.small.rawValue)
        #expect(small.rawValue == InvertibleProtocolsRequirementCountBaseline.small.rawValue)
    }
}
