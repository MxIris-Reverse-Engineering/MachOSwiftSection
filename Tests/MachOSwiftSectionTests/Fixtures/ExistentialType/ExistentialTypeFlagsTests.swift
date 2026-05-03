import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ExistentialTypeFlags`.
///
/// `ExistentialTypeFlags` is a 32-bit `OptionSet` carrying the leading
/// flags of `ExistentialTypeMetadata`. It's a pure raw-value bit decoder
/// — no MachO dependency — so the Suite re-evaluates each accessor
/// against synthetic raw values and compares against the baseline cases.
@Suite
final class ExistentialTypeFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExistentialTypeFlags"
    static var registeredTestMethodNames: Set<String> {
        ExistentialTypeFlagsBaseline.registeredTestMethodNames
    }

    @Test("init(rawValue:)") func initializer() async throws {
        for entry in ExistentialTypeFlagsBaseline.cases {
            let flags = ExistentialTypeFlags(rawValue: entry.rawValue)
            #expect(flags.rawValue == entry.rawValue)
        }
    }

    @Test func rawValue() async throws {
        for entry in ExistentialTypeFlagsBaseline.cases {
            let flags = ExistentialTypeFlags(rawValue: entry.rawValue)
            #expect(flags.rawValue == entry.rawValue)
        }
    }

    @Test func numberOfWitnessTables() async throws {
        for entry in ExistentialTypeFlagsBaseline.cases {
            let flags = ExistentialTypeFlags(rawValue: entry.rawValue)
            #expect(flags.numberOfWitnessTables == entry.numberOfWitnessTables, "numberOfWitnessTables mismatch for raw \(entry.rawValue)")
        }
    }

    @Test func classConstraint() async throws {
        for entry in ExistentialTypeFlagsBaseline.cases {
            let flags = ExistentialTypeFlags(rawValue: entry.rawValue)
            #expect(flags.classConstraint.rawValue == entry.classConstraintRawValue, "classConstraint mismatch for raw \(entry.rawValue)")
        }
    }

    @Test func hasSuperclassConstraint() async throws {
        for entry in ExistentialTypeFlagsBaseline.cases {
            let flags = ExistentialTypeFlags(rawValue: entry.rawValue)
            #expect(flags.hasSuperclassConstraint == entry.hasSuperclassConstraint, "hasSuperclassConstraint mismatch for raw \(entry.rawValue)")
        }
    }

    @Test func specialProtocol() async throws {
        for entry in ExistentialTypeFlagsBaseline.cases {
            let flags = ExistentialTypeFlags(rawValue: entry.rawValue)
            #expect(flags.specialProtocol.rawValue == entry.specialProtocolRawValue, "specialProtocol mismatch for raw \(entry.rawValue)")
        }
    }
}
