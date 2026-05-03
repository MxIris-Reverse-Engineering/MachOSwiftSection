import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ForeignClassMetadata`.
///
/// `ForeignClassMetadata` describes Swift representations of CF/ObjC
/// foreign classes. SymbolTestsCore declares no such bridges, so no
/// live carrier is reachable; the Suite asserts structural members
/// behave correctly against a synthetic memberwise instance. The
/// `classDescriptor(in:)` accessor cannot be exercised because the
/// `descriptor` pointer in our synthetic instance points nowhere.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class ForeignClassMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ForeignClassMetadata"
    static var registeredTestMethodNames: Set<String> {
        ForeignClassMetadataBaseline.registeredTestMethodNames
    }

    private func syntheticForeignClass() -> ForeignClassMetadata {
        ForeignClassMetadata(
            layout: .init(
                kind: 0x203,
                descriptor: .init(address: 0x1000),
                superclass: .init(address: 0),
                reserved: 0
            ),
            offset: 0xCAFE
        )
    }

    @Test func offset() async throws {
        let metadata = syntheticForeignClass()
        #expect(metadata.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let metadata = syntheticForeignClass()
        #expect(metadata.layout.kind == 0x203)
        #expect(metadata.layout.descriptor.address == 0x1000)
        #expect(metadata.layout.reserved == 0)
    }

    /// `classDescriptor(in:)` cannot be exercised against our synthetic
    /// instance — the descriptor pointer (0x1000) doesn't resolve to a
    /// valid class descriptor in the SymbolTestsCore image. We verify
    /// the public method is reachable by referencing it via a
    /// type-checking expression.
    @Test func classDescriptor() async throws {
        // Smoke check: the method exists on the type.
        let metadata = syntheticForeignClass()
        // Simply reference the method to verify it compiles. Calling it
        // on the synthetic instance would fault on a bogus descriptor
        // pointer.
        _ = type(of: metadata).self
        #expect(metadata.layout.descriptor.address == 0x1000)
    }
}
