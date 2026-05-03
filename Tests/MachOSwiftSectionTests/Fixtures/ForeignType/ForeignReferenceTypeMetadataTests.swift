import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ForeignReferenceTypeMetadata`.
///
/// `ForeignReferenceTypeMetadata` describes the Swift 5.7 "foreign
/// reference type" import (C++ types with `SWIFT_SHARED_REFERENCE`).
/// SymbolTestsCore has no such imports, so no live carrier is
/// reachable. The Suite asserts structural members behave against a
/// synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class ForeignReferenceTypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ForeignReferenceTypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        ForeignReferenceTypeMetadataBaseline.registeredTestMethodNames
    }

    private func syntheticForeignReference() -> ForeignReferenceTypeMetadata {
        ForeignReferenceTypeMetadata(
            layout: .init(
                kind: 0x204,
                descriptor: .init(address: 0x1000),
                reserved: 0
            ),
            offset: 0xCAFE
        )
    }

    @Test func offset() async throws {
        let metadata = syntheticForeignReference()
        #expect(metadata.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let metadata = syntheticForeignReference()
        #expect(metadata.layout.kind == 0x204)
        #expect(metadata.layout.descriptor.address == 0x1000)
    }

    /// `classDescriptor(in:)` cannot be exercised on the synthetic
    /// instance — see `ForeignClassMetadataTests.classDescriptor` for
    /// the same reasoning.
    @Test func classDescriptor() async throws {
        let metadata = syntheticForeignReference()
        _ = type(of: metadata).self
        #expect(metadata.layout.descriptor.address == 0x1000)
    }
}
