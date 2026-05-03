import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `SingletonMetadataPointer`.
///
/// `SingletonMetadataPointer` is appended to descriptors with the
/// `hasSingletonMetadataPointer` bit (cross-module canonical metadata
/// caching). The `SymbolTestsCore` fixture has no descriptor that fires
/// this bit, so no live entry is materialised. The Suite asserts the
/// type's structural members behave correctly against a synthetic
/// memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class SingletonMetadataPointerTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "SingletonMetadataPointer"
    static var registeredTestMethodNames: Set<String> {
        SingletonMetadataPointerBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let pointer = SingletonMetadataPointer(
            layout: .init(metadata: .init(relativeOffset: 0)),
            offset: 0xCAFE
        )
        #expect(pointer.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let pointer = SingletonMetadataPointer(
            layout: .init(metadata: .init(relativeOffset: 0x100)),
            offset: 0
        )
        #expect(pointer.layout.metadata.relativeOffset == 0x100)
    }
}
