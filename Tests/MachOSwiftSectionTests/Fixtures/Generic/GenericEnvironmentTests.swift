import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `GenericEnvironment`.
///
/// `GenericEnvironment` is materialized at runtime by the metadata
/// initialization machinery and is not surfaced by the static `MachOFile`
/// reader for any `SymbolTestsCore` type. The Suite registers the public
/// surface (`offset`, `layout`) for the Coverage Invariant test and
/// documents the missing runtime coverage.
@Suite
final class GenericEnvironmentTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericEnvironment"
    static var registeredTestMethodNames: Set<String> {
        GenericEnvironmentBaseline.registeredTestMethodNames
    }

    @Test func registrationOnly() async throws {
        // No live carrier surfaced by the static reader — see Generator note.
        #expect(GenericEnvironmentBaseline.registeredTestMethodNames.contains("layout"))
        #expect(GenericEnvironmentBaseline.registeredTestMethodNames.contains("offset"))
    }
}
