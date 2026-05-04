import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `DispatchClassMetadata`.
///
/// Phase C4: real InProcess test against `Classes.ClassTest.self`'s
/// runtime metadata pointer (resolved via the dlsym'd
/// `$s15SymbolTestsCore7ClassesO9ClassTestCMa` accessor).
///
/// `DispatchClassMetadata` mirrors libdispatch's runtime class layout
/// (`OS_object`'s `class_t` shape — first machine word `kind`, then
/// opaque pointer slots, then a vtable pair). It's not a Swift type
/// descriptor and SymbolTestsCore declares no `dispatch_*` carrier, so
/// instead we re-interpret an arbitrary Swift class metadata's bytes
/// through the dispatch shape. The goal is to exercise the wrapper's
/// declared accessors (`layout`, `offset`) against real runtime metadata
/// bytes; specific subfield values aren't asserted because they reflect
/// Swift class metadata interpreted through libdispatch's layout and
/// aren't meaningful as ABI literals (and the `kind` slot of Swift class
/// metadata is the isa/descriptor pointer, which is ASLR-randomized
/// per process invocation).
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class DispatchClassMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "DispatchClassMetadata"
    static var registeredTestMethodNames: Set<String> {
        DispatchClassMetadataBaseline.registeredTestMethodNames
    }

    /// Mangled symbol of the metadata accessor for
    /// `SymbolTestsCore.Classes.ClassTest`. Used by `fixtureMetadata(symbol:)`
    /// to obtain the runtime-allocated class metadata pointer.
    static let classTestMetadataSymbol = "$s15SymbolTestsCore7ClassesO9ClassTestCMa"

    @Test func layout() async throws {
        let kindRaw = try usingInProcessOnly { context in
            let pointer = try InProcessMetadataPicker.fixtureMetadata(symbol: Self.classTestMetadataSymbol)
            return try DispatchClassMetadata.resolve(at: pointer, in: context).layout.kind
        }
        // For a Swift class, the first machine word (`kind`) is the
        // descriptor / isa pointer — ASLR-randomized but always non-zero.
        // We can't pin a literal value, but we CAN assert decoded
        // `MetadataKind` resolves to `.class` from the same raw word.
        #expect(kindRaw != 0, "layout.kind should be non-zero (descriptor/isa pointer)")
        let decodedKind = MetadataKind.enumeratedMetadataKind(kindRaw)
        #expect(decodedKind == .class, "layout.kind should decode to MetadataKind.class")
    }

    @Test func offset() async throws {
        let resolvedOffset = try usingInProcessOnly { context in
            let pointer = try InProcessMetadataPicker.fixtureMetadata(symbol: Self.classTestMetadataSymbol)
            return try DispatchClassMetadata.resolve(at: pointer, in: context).offset
        }
        // For InProcess resolution, `offset` is the bit-pattern of the
        // runtime metadata pointer itself.
        let pointer = try InProcessMetadataPicker.fixtureMetadata(symbol: Self.classTestMetadataSymbol)
        let expectedOffset = Int(bitPattern: pointer)
        #expect(resolvedOffset == expectedOffset)
    }
}
