import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `CanonicalSpecializedMetadatasListEntry`.
///
/// Trailing-objects payload appended to descriptors with the
/// `hasCanonicalMetadataPrespecializations` bit. The `SymbolTestsCore`
/// fixture declares no prespecializations, so no live entry is materialised.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
@FixtureSuite
final class CanonicalSpecializedMetadatasListEntryTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    @Test func offset() async throws {
        let entry = CanonicalSpecializedMetadatasListEntry(
            layout: .init(metadata: .init(relativeOffset: 0)),
            offset: 0xCAFE
        )
        #expect(entry.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let entry = CanonicalSpecializedMetadatasListEntry(
            layout: .init(metadata: .init(relativeOffset: 0x80)),
            offset: 0
        )
        #expect(entry.layout.metadata.relativeOffset == 0x80)
    }
}
