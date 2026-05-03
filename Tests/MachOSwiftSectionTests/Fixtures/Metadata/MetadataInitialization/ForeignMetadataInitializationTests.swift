import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ForeignMetadataInitialization`.
///
/// `ForeignMetadataInitialization` is appended to descriptors with the
/// `hasForeignMetadataInitialization` bit (foreign-class bridging, e.g.
/// Core Foundation classes imported into Swift). The `SymbolTestsCore`
/// fixture declares no foreign-class types, so no live entry is
/// materialised; the Suite asserts the type's structural members behave
/// correctly against a synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class ForeignMetadataInitializationTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ForeignMetadataInitialization"
    static var registeredTestMethodNames: Set<String> {
        ForeignMetadataInitializationBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let initialization = ForeignMetadataInitialization(
            layout: .init(completionFunction: .init(relativeOffset: 0)),
            offset: 0xCAFE
        )
        #expect(initialization.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let initialization = ForeignMetadataInitialization(
            layout: .init(completionFunction: .init(relativeOffset: 0x100)),
            offset: 0
        )
        #expect(initialization.layout.completionFunction.relativeOffset == 0x100)
    }
}
