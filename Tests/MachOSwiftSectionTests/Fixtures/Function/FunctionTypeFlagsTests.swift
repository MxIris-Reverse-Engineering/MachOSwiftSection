import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `FunctionTypeFlags<UInt64>`.
///
/// Pure raw-value bit decoder — no MachO dependency. The Suite
/// re-evaluates each accessor against synthetic raw values and
/// compares against the baseline cases.
@Suite
final class FunctionTypeFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "FunctionTypeFlags"
    static var registeredTestMethodNames: Set<String> {
        FunctionTypeFlagsBaseline.registeredTestMethodNames
    }

    @Test("init(rawValue:)") func initializer() async throws {
        for entry in FunctionTypeFlagsBaseline.cases {
            let flags = FunctionTypeFlags<UInt64>(rawValue: entry.rawValue)
            #expect(flags.rawValue == entry.rawValue)
        }
    }

    @Test func rawValue() async throws {
        for entry in FunctionTypeFlagsBaseline.cases {
            let flags = FunctionTypeFlags<UInt64>(rawValue: entry.rawValue)
            #expect(flags.rawValue == entry.rawValue)
        }
    }

    @Test func numberOfParameters() async throws {
        for entry in FunctionTypeFlagsBaseline.cases {
            let flags = FunctionTypeFlags<UInt64>(rawValue: entry.rawValue)
            #expect(flags.numberOfParameters == entry.numberOfParameters)
        }
    }

    @Test func convention() async throws {
        for entry in FunctionTypeFlagsBaseline.cases {
            let flags = FunctionTypeFlags<UInt64>(rawValue: entry.rawValue)
            #expect(flags.convention.rawValue == entry.conventionRawValue)
        }
    }

    @Test func isThrowing() async throws {
        for entry in FunctionTypeFlagsBaseline.cases {
            let flags = FunctionTypeFlags<UInt64>(rawValue: entry.rawValue)
            #expect(flags.isThrowing == entry.isThrowing)
        }
    }

    @Test func isEscaping() async throws {
        for entry in FunctionTypeFlagsBaseline.cases {
            let flags = FunctionTypeFlags<UInt64>(rawValue: entry.rawValue)
            #expect(flags.isEscaping == entry.isEscaping)
        }
    }

    @Test func isAsync() async throws {
        for entry in FunctionTypeFlagsBaseline.cases {
            let flags = FunctionTypeFlags<UInt64>(rawValue: entry.rawValue)
            #expect(flags.isAsync == entry.isAsync)
        }
    }

    @Test func isSendable() async throws {
        for entry in FunctionTypeFlagsBaseline.cases {
            let flags = FunctionTypeFlags<UInt64>(rawValue: entry.rawValue)
            #expect(flags.isSendable == entry.isSendable)
        }
    }

    @Test func hasParameterFlags() async throws {
        for entry in FunctionTypeFlagsBaseline.cases {
            let flags = FunctionTypeFlags<UInt64>(rawValue: entry.rawValue)
            #expect(flags.hasParameterFlags == entry.hasParameterFlags)
        }
    }

    @Test func isDifferentiable() async throws {
        for entry in FunctionTypeFlagsBaseline.cases {
            let flags = FunctionTypeFlags<UInt64>(rawValue: entry.rawValue)
            #expect(flags.isDifferentiable == entry.isDifferentiable)
        }
    }

    @Test func hasGlobalActor() async throws {
        for entry in FunctionTypeFlagsBaseline.cases {
            let flags = FunctionTypeFlags<UInt64>(rawValue: entry.rawValue)
            #expect(flags.hasGlobalActor == entry.hasGlobalActor)
        }
    }

    @Test func hasExtendedFlags() async throws {
        for entry in FunctionTypeFlagsBaseline.cases {
            let flags = FunctionTypeFlags<UInt64>(rawValue: entry.rawValue)
            #expect(flags.hasExtendedFlags == entry.hasExtendedFlags)
        }
    }
}
