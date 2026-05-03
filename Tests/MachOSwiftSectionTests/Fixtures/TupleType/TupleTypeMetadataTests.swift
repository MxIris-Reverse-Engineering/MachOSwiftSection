import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `TupleTypeMetadata`.
///
/// `TupleTypeMetadata` is the runtime metadata for a tuple type. The
/// Swift runtime allocates these on demand; no static record is
/// reachable from the SymbolTestsCore section walks. The Suite
/// asserts the type's structural members behave correctly against
/// synthetic memberwise instances and exercises the zero-elements
/// short-circuit of `elements(in:)`.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class TupleTypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "TupleTypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        TupleTypeMetadataBaseline.registeredTestMethodNames
    }

    private func emptyTupleMetadata() -> TupleTypeMetadata {
        TupleTypeMetadata(
            layout: .init(
                kind: 0x301,
                numberOfElements: 0,
                labels: .init(address: 0)
            ),
            offset: 0xCAFE
        )
    }

    @Test func offset() async throws {
        let metadata = emptyTupleMetadata()
        #expect(metadata.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let metadata = emptyTupleMetadata()
        #expect(metadata.layout.kind == 0x301)
        #expect(metadata.layout.numberOfElements == 0)
        #expect(metadata.layout.labels.address == 0)
    }

    /// `elements(in:)` reads `numberOfElements` records starting at
    /// `offset + layoutSize`. With our synthetic instance,
    /// `numberOfElements == 0` so the read returns the empty array
    /// regardless of reader.
    @Test func elements() async throws {
        let metadata = emptyTupleMetadata()
        let viaFile = try metadata.elements(in: machOFile)
        let viaImage = try metadata.elements(in: machOImage)
        let viaContext = try metadata.elements(in: imageContext)
        #expect(viaFile.isEmpty)
        #expect(viaImage.isEmpty)
        #expect(viaContext.isEmpty)
    }
}
