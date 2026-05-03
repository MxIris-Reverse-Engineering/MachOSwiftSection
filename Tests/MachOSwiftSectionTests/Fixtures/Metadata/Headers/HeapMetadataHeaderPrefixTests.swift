import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `HeapMetadataHeaderPrefix`.
///
/// `HeapMetadataHeaderPrefix` is the single-`destroy`-pointer prefix
/// shared by every heap metadata layout. The Suite asserts the structural
/// members behave correctly against a synthetic memberwise instance —
/// the live `destroy` pointer is reachable through MachOImage but its
/// value isn't reader-stable.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class HeapMetadataHeaderPrefixTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "HeapMetadataHeaderPrefix"
    static var registeredTestMethodNames: Set<String> {
        HeapMetadataHeaderPrefixBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let prefix = HeapMetadataHeaderPrefix(
            layout: .init(destroy: .init(address: 0)),
            offset: 0xDEAD
        )
        #expect(prefix.offset == 0xDEAD)
    }

    @Test func layout() async throws {
        let prefix = HeapMetadataHeaderPrefix(
            layout: .init(destroy: .init(address: 0xCAFE)),
            offset: 0
        )
        #expect(prefix.layout.destroy.address == 0xCAFE)
    }
}
