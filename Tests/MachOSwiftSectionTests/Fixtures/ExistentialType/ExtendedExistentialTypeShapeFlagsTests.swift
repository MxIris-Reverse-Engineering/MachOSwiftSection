import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ExtendedExistentialTypeShapeFlags`.
///
/// Currently exposes only OptionSet boilerplate (`init(rawValue:)` and
/// `rawValue`). The Suite round-trips a small set of raw values to
/// catch any accidental public-surface changes.
@Suite
final class ExtendedExistentialTypeShapeFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExtendedExistentialTypeShapeFlags"
    static var registeredTestMethodNames: Set<String> {
        ExtendedExistentialTypeShapeFlagsBaseline.registeredTestMethodNames
    }

    @Test("init(rawValue:)") func initializer() async throws {
        for rawValue in ExtendedExistentialTypeShapeFlagsBaseline.rawValues {
            let flags = ExtendedExistentialTypeShapeFlags(rawValue: rawValue)
            #expect(flags.rawValue == rawValue)
        }
    }

    @Test func rawValue() async throws {
        for rawValue in ExtendedExistentialTypeShapeFlagsBaseline.rawValues {
            let flags = ExtendedExistentialTypeShapeFlags(rawValue: rawValue)
            #expect(flags.rawValue == rawValue)
        }
    }
}
