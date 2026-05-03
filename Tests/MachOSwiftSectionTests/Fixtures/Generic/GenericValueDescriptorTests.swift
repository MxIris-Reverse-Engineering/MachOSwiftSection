import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `GenericValueDescriptor`.
///
/// The `SymbolTestsCore` fixture does not declare any integer-value
/// generic type (e.g. `struct Buffer<let N: Int>`), so a live descriptor
/// cannot be sourced. The Suite registers the public surface
/// (`offset`, `layout`, `type`) for the Coverage Invariant test and
/// documents the missing runtime coverage.
@Suite
final class GenericValueDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericValueDescriptor"
    static var registeredTestMethodNames: Set<String> {
        GenericValueDescriptorBaseline.registeredTestMethodNames
    }

    @Test func registrationOnly() async throws {
        // No live carrier in SymbolTestsCore — see Generator note.
        #expect(GenericValueDescriptorBaseline.registeredTestMethodNames.contains("layout"))
        #expect(GenericValueDescriptorBaseline.registeredTestMethodNames.contains("offset"))
        #expect(GenericValueDescriptorBaseline.registeredTestMethodNames.contains("type"))
    }
}
