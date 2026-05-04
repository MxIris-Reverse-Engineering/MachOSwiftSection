import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `TupleTypeMetadata`.
///
/// Phase C2: real InProcess test against `(Int, String).self`. We resolve
/// the runtime-allocated `TupleTypeMetadata` from
/// `InProcessMetadataPicker.stdlibTupleIntString` and assert its
/// observable `layout` (kind + numberOfElements + labels), `offset`
/// (runtime metadata pointer bit-pattern), and `elements(in:)` (the
/// per-element record array) against ABI literals pinned in the
/// regenerated baseline.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class TupleTypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "TupleTypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        TupleTypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func layout() async throws {
        let resolved = try usingInProcessOnly { context in
            try TupleTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibTupleIntString, in: context)
        }
        // The runtime tuple metadata's layout: kind decodes to
        // MetadataKind.tuple (0x301); numberOfElements is 2 (Int + String);
        // labels is null because the tuple has no labels.
        #expect(resolved.kind.rawValue == TupleTypeMetadataBaseline.stdlibTupleIntString.kindRawValue)
        #expect(resolved.layout.numberOfElements == TupleTypeMetadataBaseline.stdlibTupleIntString.numberOfElements)
        #expect(resolved.layout.labels.address == TupleTypeMetadataBaseline.stdlibTupleIntString.labelsAddress)
    }

    @Test func offset() async throws {
        let resolvedOffset = try usingInProcessOnly { context in
            try TupleTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibTupleIntString, in: context).offset
        }
        // For InProcess resolution, `offset` is the bit-pattern of the
        // runtime metadata pointer itself.
        let expectedOffset = Int(bitPattern: InProcessMetadataPicker.stdlibTupleIntString)
        #expect(resolvedOffset == expectedOffset)
    }

    @Test func elements() async throws {
        let elementCount = try usingInProcessOnly { context in
            let tuple = try TupleTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibTupleIntString, in: context)
            return try tuple.elements(in: context).count
        }
        // `(Int, String)` has 2 elements.
        #expect(elementCount == Int(TupleTypeMetadataBaseline.stdlibTupleIntString.numberOfElements))
    }
}
