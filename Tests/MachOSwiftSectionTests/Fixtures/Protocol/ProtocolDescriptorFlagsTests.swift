import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ProtocolDescriptorFlags`.
///
/// `ProtocolDescriptorFlags` is the standalone 32-bit flag word used by
/// the runtime metadata sections (NOT the kind-specific flags reachable
/// via `ContextDescriptorFlags`). The fixture has no live carrier, so
/// the Suite exercises the flag accessors against synthetic raw values
/// embedded in the baseline.
@Suite
final class ProtocolDescriptorFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ProtocolDescriptorFlags"
    static var registeredTestMethodNames: Set<String> {
        ProtocolDescriptorFlagsBaseline.registeredTestMethodNames
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        let flags = ProtocolDescriptorFlags(rawValue: ProtocolDescriptorFlagsBaseline.swift.rawValue)
        #expect(flags.rawValue == ProtocolDescriptorFlagsBaseline.swift.rawValue)
    }

    @Test func rawValue() async throws {
        let flags = ProtocolDescriptorFlags(rawValue: ProtocolDescriptorFlagsBaseline.resilient.rawValue)
        #expect(flags.rawValue == ProtocolDescriptorFlagsBaseline.resilient.rawValue)
    }

    @Test func isSwift() async throws {
        let swiftFlags = ProtocolDescriptorFlags(rawValue: ProtocolDescriptorFlagsBaseline.swift.rawValue)
        #expect(swiftFlags.isSwift == ProtocolDescriptorFlagsBaseline.swift.isSwift)

        let objcFlags = ProtocolDescriptorFlags(rawValue: ProtocolDescriptorFlagsBaseline.objc.rawValue)
        #expect(objcFlags.isSwift == ProtocolDescriptorFlagsBaseline.objc.isSwift)
    }

    @Test func isResilient() async throws {
        let swiftFlags = ProtocolDescriptorFlags(rawValue: ProtocolDescriptorFlagsBaseline.swift.rawValue)
        #expect(swiftFlags.isResilient == ProtocolDescriptorFlagsBaseline.swift.isResilient)

        let resilientFlags = ProtocolDescriptorFlags(rawValue: ProtocolDescriptorFlagsBaseline.resilient.rawValue)
        #expect(resilientFlags.isResilient == ProtocolDescriptorFlagsBaseline.resilient.isResilient)
    }

    @Test func classConstraint() async throws {
        let flags = ProtocolDescriptorFlags(rawValue: ProtocolDescriptorFlagsBaseline.swift.rawValue)
        #expect(flags.classConstraint.rawValue == ProtocolDescriptorFlagsBaseline.swift.classConstraintRawValue)
    }

    @Test func dispatchStrategy() async throws {
        let swiftFlags = ProtocolDescriptorFlags(rawValue: ProtocolDescriptorFlagsBaseline.swift.rawValue)
        #expect(swiftFlags.dispatchStrategy.rawValue == ProtocolDescriptorFlagsBaseline.swift.dispatchStrategyRawValue)

        let objcFlags = ProtocolDescriptorFlags(rawValue: ProtocolDescriptorFlagsBaseline.objc.rawValue)
        #expect(objcFlags.dispatchStrategy.rawValue == ProtocolDescriptorFlagsBaseline.objc.dispatchStrategyRawValue)
    }

    @Test func specialProtocolKind() async throws {
        let flags = ProtocolDescriptorFlags(rawValue: ProtocolDescriptorFlagsBaseline.swift.rawValue)
        #expect(flags.specialProtocolKind.rawValue == ProtocolDescriptorFlagsBaseline.swift.specialProtocolKindRawValue)
    }

    @Test func needsProtocolWitnessTable() async throws {
        let swiftFlags = ProtocolDescriptorFlags(rawValue: ProtocolDescriptorFlagsBaseline.swift.rawValue)
        #expect(swiftFlags.needsProtocolWitnessTable == ProtocolDescriptorFlagsBaseline.swift.needsProtocolWitnessTable)

        let objcFlags = ProtocolDescriptorFlags(rawValue: ProtocolDescriptorFlagsBaseline.objc.rawValue)
        #expect(objcFlags.needsProtocolWitnessTable == ProtocolDescriptorFlagsBaseline.objc.needsProtocolWitnessTable)
    }
}
