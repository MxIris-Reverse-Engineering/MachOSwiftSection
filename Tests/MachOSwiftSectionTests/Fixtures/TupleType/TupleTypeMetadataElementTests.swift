import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `TupleTypeMetadata.Element`.
///
/// Phase C2: real InProcess test against the first element of
/// `(Int, String).self`'s `TupleTypeMetadata`. We resolve the
/// runtime-allocated tuple metadata, read its element records, and
/// assert the first element's `type`/`offset` against ABI literals
/// pinned in the regenerated baseline.
///
/// `Element` is the nested struct describing a single tuple element
/// (its metadata pointer plus byte offset). `PublicMemberScanner`
/// keys nested types by their inner struct name, so the
/// `testedTypeName` here is `"Element"`.
@Suite
final class TupleTypeMetadataElementTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "Element"
    static var registeredTestMethodNames: Set<String> {
        TupleTypeMetadataElementBaseline.registeredTestMethodNames
    }

    @Test func type() async throws {
        let address = try usingInProcessOnly { context in
            let tuple = try TupleTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibTupleIntString, in: context)
            return try tuple.elements(in: context).first!.type.address
        }
        // First element of `(Int, String)` is `Int` — pointer must equal
        // the bit pattern of `Int.self`'s metadata pointer.
        let expectedAddress = UInt64(UInt(bitPattern: unsafeBitCast(Int.self, to: UnsafeRawPointer.self)))
        #expect(address == expectedAddress)
    }

    @Test func offset() async throws {
        let result = try usingInProcessOnly { context in
            let tuple = try TupleTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibTupleIntString, in: context)
            return try tuple.elements(in: context).first!.offset
        }
        #expect(result == TupleTypeMetadataElementBaseline.firstElementOfIntStringTuple.offset)
    }
}
