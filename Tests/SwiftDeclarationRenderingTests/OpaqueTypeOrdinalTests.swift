import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDeclarationRendering
import Demangling
@_spi(Internals) import SwiftInspection
@_spi(Internals) import SwiftSymbols
import SwiftSectionFixtureSupport

/// A declaration may produce more than one opaque type — `-> Pair<some P, some P>`
/// is two — and the demangled `opaqueType` node says which one it is in its
/// second child, the **ordinal**. The opaque type descriptor's underlying-type
/// array is indexed by exactly that ordinal.
///
/// The rewriter used to read element 0 unconditionally, so every `some` of such
/// a declaration rendered as its first one. Nothing raised and nothing looked
/// degraded: the output was a real, fully-qualified, wrong type.
///
/// Pinned against a compiled fixture rather than a system framework because
/// SwiftUI and SwiftUICore have no such shape — every opaque reference in their
/// associated-type records carries ordinal 0, which is precisely why the defect
/// survived a full dump of both.
@Suite
struct OpaqueTypeOrdinalTests {
    /// `Anchor` keeps a `__DATA` segment in the dylib (see AGENTS.md,
    /// "On-the-fly-compiled fixture dylibs need a class").
    ///
    /// `makeOpaquePair` is the whole point: ONE declaration, TWO `some`
    /// results, with deliberately different underlying types so an
    /// ordinal-blind read is visible rather than coincidentally right.
    private static let fixtureSource = """
    public final class Anchor {}

    public protocol ProbeView {
        associatedtype Body: ProbeView
        var body: Body { get }
    }

    public struct ProbeNever: ProbeView {
        public var body: ProbeNever { fatalError() }
    }

    public struct ProbeLeafA: ProbeView {
        public init() {}
        public var body: ProbeNever { fatalError() }
    }

    public struct ProbeLeafB: ProbeView {
        public init() {}
        public var body: ProbeNever { fatalError() }
    }

    public struct ProbePair<First: ProbeView, Second: ProbeView>: ProbeView {
        public var first: First
        public var second: Second
        public init(first: First, second: Second) {
            self.first = first
            self.second = second
        }
        public var body: ProbeNever { fatalError() }
    }

    public func makeOpaquePair() -> ProbePair<some ProbeView, some ProbeView> {
        ProbePair(first: ProbeLeafA(), second: ProbeLeafB())
    }
    """

    private func loadFixtureMachOFile() throws -> MachOFile {
        let libraryURL = try FixtureCompiler.shared.dynamicLibrary(
            named: "OpaqueTypeOrdinalFixture",
            language: .swift,
            source: Self.fixtureSource,
            arguments: ["-target", "arm64-apple-macosx15.0"]
        )
        return try HostSlice.machOFile(at: libraryURL)
    }

    /// `…QOMQ` is the opaque type descriptor's own symbol; `makeOpaquePair`'s
    /// mangles its two results as `Qr` and `QR_`, which is what makes it the
    /// two-ordinal fixture.
    private func opaqueTypeDescriptorOffset(in machOFile: MachOFile) throws -> Int {
        let symbols = SwiftSymbolIndexStore.shared.symbols(of: .opaqueTypeDescriptor, in: machOFile)
        // Taken as the only one rather than matched by name: `makeOpaquePair`
        // is not a substring of its own symbol, because the mangler
        // substitutes the repeated module prefix and spells it `04makeA4Pair`.
        // The fixture declares exactly one opaque-producing declaration, and
        // the count assertion is what keeps that true if it ever gains another.
        #expect(
            symbols.count == 1,
            Comment(rawValue: "the fixture must declare exactly one opaque-producing declaration, found \(symbols.map(\.name))")
        )
        return try #require(symbols.first, "the fixture carries no opaque type descriptor symbol").offset
    }

    /// The layout the ordinal indexes into: every replacement type first, then
    /// the conformances — the order IRGen writes the underlying substitution
    /// map in and the order the runtime's `_getOpaqueTypeMetadata` reads back.
    @MainActor
    @Test func underlyingTypeArgumentsAreOrderedTypesFirstThenConformances() async throws {
        let machOFile = try loadFixtureMachOFile()
        let descriptor = try OpaqueTypeDescriptor.resolve(at: opaqueTypeDescriptorOffset(in: machOFile), in: machOFile.context)
        let opaqueType = try OpaqueType(descriptor: descriptor, in: machOFile.context)

        #expect(
            descriptor.numUnderlyingTypeArguments == 4,
            "two opaque results with one conformance each: \(descriptor.numUnderlyingTypeArguments)"
        )

        var rendered: [String] = []
        for mangledName in opaqueType.underlyingTypeArgumentMangledNames {
            let node = try SymbolicDemangler.demangleType(for: mangledName, in: machOFile.context)
            rendered.append(await node.print(using: DemangleOptions.default))
        }

        #expect(rendered.count >= 2, "expected at least the two underlying types, got \(rendered)")
        #expect(
            rendered[0] == "OpaqueTypeOrdinalFixture.ProbeLeafA",
            "ordinal 0's underlying type must be the FIRST `some` result, got \(rendered[0])"
        )
        #expect(
            rendered[1] == "OpaqueTypeOrdinalFixture.ProbeLeafB",
            "ordinal 1's underlying type must be the SECOND `some` result, got \(rendered[1])"
        )
        #expect(
            rendered[0] != rendered[1],
            "the fixture must keep the two results distinguishable, else an ordinal-blind read passes by luck"
        )
    }

    /// The end-to-end consequence: resolving the opaque type at ordinal 1 must
    /// yield the second result. Driven through `resolveOpaqueType(in:)` on a
    /// hand-built node, because the compiler substitutes the underlying types
    /// straight into its own reflection records — a fixture cannot produce an
    /// associated-type record that still references the descriptor.
    @MainActor
    @Test func resolvingByOrdinalYieldsThatOrdinalsUnderlyingType() async throws {
        let machOFile = try loadFixtureMachOFile()
        let descriptorOffset = try opaqueTypeDescriptorOffset(in: machOFile)

        func resolvedOpaqueType(ordinal: UInt64) async throws -> String {
            let opaqueTypeNode = Node.create(
                kind: .type,
                children: [
                    Node.create(
                        kind: .opaqueType,
                        children: [
                            Node.create(kind: .opaqueTypeDescriptorSymbolicReference, index: UInt64(descriptorOffset)),
                            Node.create(kind: .index, index: ordinal),
                            Node.create(kind: .typeList, children: []),
                        ]
                    ),
                ]
            )
            return await (try opaqueTypeNode.resolveOpaqueType(in: machOFile)).print(using: DemangleOptions.default)
        }

        #expect(try await resolvedOpaqueType(ordinal: 0) == "OpaqueTypeOrdinalFixture.ProbeLeafA")
        #expect(
            try await resolvedOpaqueType(ordinal: 1) == "OpaqueTypeOrdinalFixture.ProbeLeafB",
            "ordinal 1 resolving to ProbeLeafA is the defect: the array is read at 0 regardless of the ordinal"
        )
    }
}
