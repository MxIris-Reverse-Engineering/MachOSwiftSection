import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `BorrowTypeMetadata`.
///
/// `BorrowTypeMetadata` (kind `0x309`) is the runtime metadata for a
/// `Builtin.Borrow<T>` value, introduced by the Swift 6.4 runtime. The
/// runtime allocates it lazily through `swift_getBorrowTypeMetadata`; no
/// binary section ever carries one, so the static section walks cannot
/// reach an instance and the `SymbolTestsCore` fixture declares none. The
/// Suite asserts the wrapper's structural members against a synthetic
/// memberwise instance; the live path is exercised by
/// `RuntimeMetadataTypeBuilderTests` on a Swift 6.4 runtime.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class BorrowTypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "BorrowTypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        BorrowTypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let metadata = BorrowTypeMetadata(
            layout: .init(kind: 0x309, referent: .init(address: 0)),
            offset: 0xCAFE
        )
        #expect(metadata.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let metadata = BorrowTypeMetadata(
            layout: .init(kind: 0x309, referent: .init(address: 0x42)),
            offset: 0
        )
        #expect(metadata.layout.kind == 0x309)
        #expect(metadata.kind == .borrow)
        #expect(metadata.layout.referent.address == 0x42)
    }
}
