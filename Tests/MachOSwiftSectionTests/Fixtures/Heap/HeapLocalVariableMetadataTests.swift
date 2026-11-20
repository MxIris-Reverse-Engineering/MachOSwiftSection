import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `HeapLocalVariableMetadata`.
///
/// Runtime-allocated metadata; no static carrier is reachable from
/// SymbolTestsCore. The Suite asserts structural members behave
/// against a synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
@FixtureSuite
final class HeapLocalVariableMetadataTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    @Test func offset() async throws {
        let metadata = HeapLocalVariableMetadata(
            layout: .init(
                kind: 0x400,
                offsetToFirstCapture: 0x10,
                captureDescription: .init(address: 0x1000)
            ),
            offset: 0xCAFE
        )
        #expect(metadata.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let metadata = HeapLocalVariableMetadata(
            layout: .init(
                kind: 0x400,
                offsetToFirstCapture: 0x18,
                captureDescription: .init(address: 0x2000)
            ),
            offset: 0
        )
        #expect(metadata.layout.kind == 0x400)
        #expect(metadata.layout.offsetToFirstCapture == 0x18)
        #expect(metadata.layout.captureDescription.address == 0x2000)
    }
}
