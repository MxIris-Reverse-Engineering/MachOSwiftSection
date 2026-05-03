import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ValueWitnessFlags`.
///
/// Pure raw-value bit decoder — no MachO dependency. The Suite
/// re-evaluates each accessor against synthetic raw values and compares
/// against the baseline cases. The static `let` option-set constants
/// (e.g. `isNonPOD`) are exercised indirectly via the inverted
/// instance-level accessors (`isPOD = !contains(.isNonPOD)`); separate
/// static-constant smoke checks verify the raw-value constants haven't
/// drifted.
@Suite
final class ValueWitnessFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ValueWitnessFlags"
    static var registeredTestMethodNames: Set<String> {
        ValueWitnessFlagsBaseline.registeredTestMethodNames
    }

    @Test("init(rawValue:)") func initializer() async throws {
        for entry in ValueWitnessFlagsBaseline.cases {
            let flags = ValueWitnessFlags(rawValue: entry.rawValue)
            #expect(flags.rawValue == entry.rawValue)
        }
    }

    @Test func rawValue() async throws {
        for entry in ValueWitnessFlagsBaseline.cases {
            let flags = ValueWitnessFlags(rawValue: entry.rawValue)
            #expect(flags.rawValue == entry.rawValue)
        }
    }

    @Test func alignmentMask() async throws {
        for entry in ValueWitnessFlagsBaseline.cases {
            let flags = ValueWitnessFlags(rawValue: entry.rawValue)
            #expect(flags.alignmentMask == entry.alignmentMask)
        }
    }

    @Test func alignment() async throws {
        for entry in ValueWitnessFlagsBaseline.cases {
            let flags = ValueWitnessFlags(rawValue: entry.rawValue)
            #expect(flags.alignment == entry.alignment)
        }
    }

    @Test func isPOD() async throws {
        for entry in ValueWitnessFlagsBaseline.cases {
            let flags = ValueWitnessFlags(rawValue: entry.rawValue)
            #expect(flags.isPOD == entry.isPOD)
        }
    }

    @Test func isNonPOD() async throws {
        // Static `let isNonPOD = ValueWitnessFlags(rawValue: 0x0001_0000)`.
        #expect(ValueWitnessFlags.isNonPOD.rawValue == 0x0001_0000)
    }

    @Test func isInlineStorage() async throws {
        for entry in ValueWitnessFlagsBaseline.cases {
            let flags = ValueWitnessFlags(rawValue: entry.rawValue)
            #expect(flags.isInlineStorage == entry.isInlineStorage)
        }
    }

    @Test func isNonInline() async throws {
        #expect(ValueWitnessFlags.isNonInline.rawValue == 0x0002_0000)
    }

    @Test func isBitwiseTakable() async throws {
        for entry in ValueWitnessFlagsBaseline.cases {
            let flags = ValueWitnessFlags(rawValue: entry.rawValue)
            #expect(flags.isBitwiseTakable == entry.isBitwiseTakable)
        }
    }

    @Test func isNonBitwiseTakable() async throws {
        #expect(ValueWitnessFlags.isNonBitwiseTakable.rawValue == 0x0010_0000)
    }

    @Test func isBitwiseBorrowable() async throws {
        for entry in ValueWitnessFlagsBaseline.cases {
            let flags = ValueWitnessFlags(rawValue: entry.rawValue)
            #expect(flags.isBitwiseBorrowable == entry.isBitwiseBorrowable)
        }
    }

    @Test func isNonBitwiseBorrowable() async throws {
        #expect(ValueWitnessFlags.isNonBitwiseBorrowable.rawValue == 0x0100_0000)
    }

    @Test func isCopyable() async throws {
        for entry in ValueWitnessFlagsBaseline.cases {
            let flags = ValueWitnessFlags(rawValue: entry.rawValue)
            #expect(flags.isCopyable == entry.isCopyable)
        }
    }

    @Test func isNonCopyable() async throws {
        #expect(ValueWitnessFlags.isNonCopyable.rawValue == 0x0080_0000)
    }

    @Test func hasEnumWitnesses() async throws {
        for entry in ValueWitnessFlagsBaseline.cases {
            let flags = ValueWitnessFlags(rawValue: entry.rawValue)
            #expect(flags.hasEnumWitnesses == entry.hasEnumWitnesses)
        }
        // Static constant value.
        #expect(ValueWitnessFlags.hasEnumWitnesses.rawValue == 0x0020_0000)
    }

    @Test func hasSpareBits() async throws {
        #expect(ValueWitnessFlags.hasSpareBits.rawValue == 0x0008_0000)
    }

    @Test func isIncomplete() async throws {
        for entry in ValueWitnessFlagsBaseline.cases {
            let flags = ValueWitnessFlags(rawValue: entry.rawValue)
            #expect(flags.isIncomplete == entry.isIncomplete)
        }
    }

    @Test func inComplete() async throws {
        #expect(ValueWitnessFlags.inComplete.rawValue == 0x0040_0000)
    }

    @Test func maxNumExtraInhabitants() async throws {
        #expect(ValueWitnessFlags.maxNumExtraInhabitants == 0x7FFF_FFFF)
    }
}
