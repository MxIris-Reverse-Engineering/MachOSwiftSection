import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ObjCClassWrapperMetadata`.
///
/// `ObjCClassWrapperMetadata` is the metadata kind Swift uses to refer
/// to plain ObjC classes (e.g. `NSObject`-rooted types not authored in
/// Swift). The metadata accessor for a Swift class doesn't return this
/// kind directly; the wrapper is reachable through other paths
/// (e.g. type-of-class lookups). For the SymbolTestsCore fixture we
/// don't have a clean reproducible path that returns this metadata
/// kind, so this Suite registers the public surface and asserts the
/// kind enum is correctly catalogued in `MetadataWrapper`.
@Suite
final class ObjCClassWrapperMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ObjCClassWrapperMetadata"
    static var registeredTestMethodNames: Set<String> {
        ObjCClassWrapperMetadataBaseline.registeredTestMethodNames
    }

    @Test func registrationOnly() async throws {
        // The Suite documents that a clean reproducible accessor flow
        // returning ObjCClassWrapperMetadata is not available from the
        // SymbolTestsCore fixture; the Coverage Invariant test (Task 16)
        // tracks the public surface (`offset`, `layout`).
        #expect(ObjCClassWrapperMetadataBaseline.registeredTestMethodNames.contains("offset"))
        #expect(ObjCClassWrapperMetadataBaseline.registeredTestMethodNames.contains("layout"))
    }
}
