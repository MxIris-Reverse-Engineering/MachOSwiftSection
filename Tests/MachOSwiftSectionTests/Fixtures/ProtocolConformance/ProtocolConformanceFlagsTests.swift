import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ProtocolConformanceFlags`.
///
/// The 32-bit flag word stored in `ProtocolConformanceDescriptor.Layout.flags`.
/// Each accessor is exercised via the live raw values harvested from the
/// fixture's pickers (encoded into the baseline). The Suite re-instantiates
/// `ProtocolConformanceFlags(rawValue: ...)` on the literal raw values and
/// asserts each accessor against the baseline literal — this validates both
/// the bitfield parsing and the `init(rawValue:)`/`rawValue` round-trip.
@Suite
final class ProtocolConformanceFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ProtocolConformanceFlags"
    static var registeredTestMethodNames: Set<String> {
        ProtocolConformanceFlagsBaseline.registeredTestMethodNames
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        let flags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.structTestProtocolTest.rawValue)
        #expect(flags.rawValue == ProtocolConformanceFlagsBaseline.structTestProtocolTest.rawValue)
    }

    @Test func rawValue() async throws {
        let flags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.conditionalFirst.rawValue)
        #expect(flags.rawValue == ProtocolConformanceFlagsBaseline.conditionalFirst.rawValue)
    }

    @Test func typeReferenceKind() async throws {
        let flags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.structTestProtocolTest.rawValue)
        #expect(flags.typeReferenceKind.rawValue == ProtocolConformanceFlagsBaseline.structTestProtocolTest.typeReferenceKindRawValue)
    }

    @Test func isRetroactive() async throws {
        let structTestFlags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.structTestProtocolTest.rawValue)
        #expect(structTestFlags.isRetroactive == ProtocolConformanceFlagsBaseline.structTestProtocolTest.isRetroactive)

        let conditionalFlags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.conditionalFirst.rawValue)
        #expect(conditionalFlags.isRetroactive == ProtocolConformanceFlagsBaseline.conditionalFirst.isRetroactive)
    }

    @Test func isSynthesizedNonUnique() async throws {
        let flags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.structTestProtocolTest.rawValue)
        #expect(flags.isSynthesizedNonUnique == ProtocolConformanceFlagsBaseline.structTestProtocolTest.isSynthesizedNonUnique)
    }

    @Test func isConformanceOfProtocol() async throws {
        let flags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.structTestProtocolTest.rawValue)
        #expect(flags.isConformanceOfProtocol == ProtocolConformanceFlagsBaseline.structTestProtocolTest.isConformanceOfProtocol)
    }

    @Test func hasGlobalActorIsolation() async throws {
        let structTestFlags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.structTestProtocolTest.rawValue)
        #expect(structTestFlags.hasGlobalActorIsolation == ProtocolConformanceFlagsBaseline.structTestProtocolTest.hasGlobalActorIsolation)

        let globalActorFlags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.globalActorFirst.rawValue)
        #expect(globalActorFlags.hasGlobalActorIsolation == ProtocolConformanceFlagsBaseline.globalActorFirst.hasGlobalActorIsolation)
    }

    @Test func hasNonDefaultSerialExecutorIsIsolatingCurrentContext() async throws {
        let flags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.structTestProtocolTest.rawValue)
        #expect(flags.hasNonDefaultSerialExecutorIsIsolatingCurrentContext == ProtocolConformanceFlagsBaseline.structTestProtocolTest.hasNonDefaultSerialExecutorIsIsolatingCurrentContext)
    }

    @Test func hasResilientWitnesses() async throws {
        let structTestFlags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.structTestProtocolTest.rawValue)
        #expect(structTestFlags.hasResilientWitnesses == ProtocolConformanceFlagsBaseline.structTestProtocolTest.hasResilientWitnesses)

        let resilientFlags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.resilientFirst.rawValue)
        #expect(resilientFlags.hasResilientWitnesses == ProtocolConformanceFlagsBaseline.resilientFirst.hasResilientWitnesses)
    }

    @Test func hasGenericWitnessTable() async throws {
        let flags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.structTestProtocolTest.rawValue)
        #expect(flags.hasGenericWitnessTable == ProtocolConformanceFlagsBaseline.structTestProtocolTest.hasGenericWitnessTable)
    }

    @Test func numConditionalRequirements() async throws {
        let structTestFlags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.structTestProtocolTest.rawValue)
        #expect(structTestFlags.numConditionalRequirements == ProtocolConformanceFlagsBaseline.structTestProtocolTest.numConditionalRequirements)

        let conditionalFlags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.conditionalFirst.rawValue)
        #expect(conditionalFlags.numConditionalRequirements == ProtocolConformanceFlagsBaseline.conditionalFirst.numConditionalRequirements)
    }

    @Test func numConditionalPackShapeDescriptors() async throws {
        let flags = ProtocolConformanceFlags(rawValue: ProtocolConformanceFlagsBaseline.structTestProtocolTest.rawValue)
        #expect(flags.numConditionalPackShapeDescriptors == ProtocolConformanceFlagsBaseline.structTestProtocolTest.numConditionalPackShapeDescriptors)
    }
}
