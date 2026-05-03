import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `FunctionTypeMetadata`.
///
/// Runtime-allocated metadata; no static carrier is reachable from
/// SymbolTestsCore. The Suite asserts structural members behave
/// against a synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class FunctionTypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "FunctionTypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        FunctionTypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let metadata = FunctionTypeMetadata(
            layout: .init(
                kind: 0x302,
                flags: .init(rawValue: 0x0000_0000_0000_0002),
                resultType: .init(address: 0x1000)
            ),
            offset: 0xCAFE
        )
        #expect(metadata.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let metadata = FunctionTypeMetadata(
            layout: .init(
                kind: 0x302,
                flags: .init(rawValue: 0x0000_0000_0000_0003),
                resultType: .init(address: 0x2000)
            ),
            offset: 0
        )
        #expect(metadata.layout.kind == 0x302)
        #expect(metadata.layout.flags.numberOfParameters == 3)
        #expect(metadata.layout.resultType.address == 0x2000)
    }
}
