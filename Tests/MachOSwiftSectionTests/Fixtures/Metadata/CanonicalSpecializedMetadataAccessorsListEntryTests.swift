import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `CanonicalSpecializedMetadataAccessorsListEntry`.
///
/// `CanonicalSpecializedMetadataAccessorsListEntry` is a trailing-objects
/// payload appended to descriptors with the
/// `hasCanonicalMetadataPrespecializations` bit. The `SymbolTestsCore`
/// fixture declares no `@_specialize` / canonical-metadata prespecialization
/// directives, so no live entry is reachable through the static section
/// walks. The Suite asserts the type's structural members behave correctly
/// against a synthetic memberwise instance; live runtime payloads will be
/// exercised when prespecialized fixtures are added.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class CanonicalSpecializedMetadataAccessorsListEntryTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "CanonicalSpecializedMetadataAccessorsListEntry"
    static var registeredTestMethodNames: Set<String> {
        CanonicalSpecializedMetadataAccessorsListEntryBaseline.registeredTestMethodNames
    }

    /// `offset` is set by the memberwise initialiser; cross-reader
    /// agreement is trivial (no MachO read is involved).
    @Test func offset() async throws {
        let entry = CanonicalSpecializedMetadataAccessorsListEntry(
            layout: .init(accessor: .init(relativeOffset: 0)),
            offset: 0xCAFE
        )
        #expect(entry.offset == 0xCAFE)
    }

    /// `layout` exposes the relative-direct accessor pointer; we verify
    /// the round-trip through the memberwise initialiser preserves the
    /// supplied raw offset.
    @Test func layout() async throws {
        let entry = CanonicalSpecializedMetadataAccessorsListEntry(
            layout: .init(accessor: .init(relativeOffset: 0x100)),
            offset: 0
        )
        #expect(entry.layout.accessor.relativeOffset == 0x100)
    }
}
