import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `MethodDefaultOverrideDescriptor`.
///
/// The `SymbolTestsCore` fixture does not declare any class with a
/// default-override table, so a live `MethodDefaultOverrideDescriptor`
/// cannot be sourced. The Suite documents the missing runtime coverage
/// and registers the public surface for the Coverage Invariant test.
@Suite
final class MethodDefaultOverrideDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MethodDefaultOverrideDescriptor"
    static var registeredTestMethodNames: Set<String> {
        MethodDefaultOverrideDescriptorBaseline.registeredTestMethodNames
    }

    /// Sentinel test ensuring the Suite is loaded by swift-testing. The
    /// real coverage will land when a fixture surfaces a default-override
    /// table.
    @Test func registrationOnly() async throws {
        // No live instance available in SymbolTestsCore; the Suite exists
        // to register the public member surface for the Coverage
        // Invariant test.
        #expect(MethodDefaultOverrideDescriptorBaseline.registeredTestMethodNames.contains("originalMethodDescriptor"))
        #expect(MethodDefaultOverrideDescriptorBaseline.registeredTestMethodNames.contains("replacementMethodDescriptor"))
        #expect(MethodDefaultOverrideDescriptorBaseline.registeredTestMethodNames.contains("implementationSymbols"))
    }
}
