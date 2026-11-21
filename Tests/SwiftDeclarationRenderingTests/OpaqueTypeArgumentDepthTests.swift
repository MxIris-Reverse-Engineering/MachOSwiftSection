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

/// An opaque type reference spells its generic arguments as one list per
/// declaration around the opaque result, outermost first, and the mangler
/// writes a list for EVERY such declaration — an empty one for a level that
/// declares no parameter (`ASTMangler::appendBoundGenericArgs`). A parameter's
/// depth counts only the levels that declare parameters, so a list's position
/// is not its depth: the runtime flattens the lists and regroups them by the
/// descriptor's own depths (`resolveOpaqueType` → `_gatherGenericParameters`).
///
/// Taking the position for the depth left the parameter of a generic function
/// in a non-generic type unsubstituted — Xcodes' `MainToolbarModifier.Body`
/// printed `SwiftUI.TupleToolbarContent<A>` inside a type that has no
/// parameters — and, with a generic type nested in a non-generic one, read the
/// type's argument as the function's: a real, wrong type.
///
/// Driven through `resolveOpaqueType(in:)` on a hand-built node, as
/// `OpaqueTypeOrdinalTests` does: the compiler substitutes an opaque type it
/// can see through into the module's own reflection records, so a fixture
/// cannot produce a record that still references the descriptor. The node
/// carries the argument lists the mangler writes for these declarations.
@Suite
struct OpaqueTypeArgumentDepthTests {
    private static let moduleName = "OpaqueTypeArgumentDepthFixture"

    /// `FixtureAnchor` is ballast: a fixture dylib with no class has no
    /// `__DATA` segment, which older MachOKit releases mis-walked.
    ///
    /// `ProbeNamespace` declares no parameter, so the mangler writes an empty
    /// list for it in front of every list below it: `makeWrapper`'s lists are
    /// `[[], [Element]]`, and `Box.makePair`'s are `[[], [Boxed], [Extra]]`.
    private static let fixtureSource = """
    public final class FixtureAnchor {}

    public protocol ProbeShape {}

    public struct ProbeWrapper<Wrapped>: ProbeShape {
        public var wrapped: Wrapped
        public init(wrapped: Wrapped) { self.wrapped = wrapped }
    }

    public struct ProbePair<First, Second>: ProbeShape {
        public var first: First
        public var second: Second
        public init(first: First, second: Second) {
            self.first = first
            self.second = second
        }
    }

    public enum ProbeNamespace {
        public static func makeWrapper<Element>(_ element: Element) -> some ProbeShape {
            ProbeWrapper(wrapped: element)
        }

        public struct Box<Boxed> {
            public var boxed: Boxed
            public init(boxed: Boxed) { self.boxed = boxed }

            public func makePair<Extra>(_ extra: Extra) -> some ProbeShape {
                ProbePair(first: boxed, second: extra)
            }
        }
    }
    """

    private func loadFixtureMachOFile() throws -> MachOFile {
        let libraryURL = try FixtureCompiler.shared.dynamicLibrary(
            named: Self.moduleName,
            language: .swift,
            source: Self.fixtureSource,
            arguments: ["-swift-version", "5", "-target", "arm64-apple-macosx15.0"]
        )
        return try HostSlice.machOFile(at: libraryURL)
    }

    /// The offset of the opaque type descriptor of the declaration named
    /// `declarationName`, found by its demangled symbol.
    private func opaqueTypeDescriptorOffset(ofDeclarationNamed declarationName: String, in machOFile: MachOFile) throws -> Int {
        let symbols = SwiftSymbolIndexStore.shared.symbols(of: .opaqueTypeDescriptor, in: machOFile)
        let symbol = symbols.first { $0.demangledNode.materialize().print(using: .default).contains(declarationName) }
        return try #require(symbol, "no opaque type descriptor names \(declarationName): \(symbols.map { $0.demangledNode.materialize().print(using: .default) })").offset
    }

    /// The underlying type of `declarationName`'s opaque result, resolved for
    /// a reference carrying `argumentListsByLevel` — one list per declaration
    /// around the result, as the mangler writes them.
    private func resolvedUnderlyingType(ofDeclarationNamed declarationName: String, argumentListsByLevel: [[Node]]) async throws -> String {
        let machOFile = try loadFixtureMachOFile()
        let descriptorOffset = try opaqueTypeDescriptorOffset(ofDeclarationNamed: declarationName, in: machOFile)
        let opaqueTypeNode = Node.create(
            kind: .type,
            children: [
                Node.create(
                    kind: .opaqueType,
                    children: [
                        Node.create(kind: .opaqueTypeDescriptorSymbolicReference, index: UInt64(descriptorOffset)),
                        Node.create(kind: .index, index: 0),
                        Node.create(kind: .typeList, children: argumentListsByLevel.map { Node.create(kind: .typeList, children: $0) }),
                    ]
                ),
            ]
        )
        return await (try opaqueTypeNode.resolveOpaqueType(in: machOFile)).print(using: DemangleOptions.default)
    }

    @Test("a generic function's argument is substituted when its type declares no parameter")
    func argumentOfAGenericFunctionInANonGenericTypeIsSubstituted() async throws {
        let integerType = try await demangleAsNode("Si", isType: true)

        let resolved = try await resolvedUnderlyingType(ofDeclarationNamed: "makeWrapper", argumentListsByLevel: [[], [integerType]])

        #expect(resolved == "\(Self.moduleName).ProbeWrapper<Swift.Int>")
    }

    @Test("each argument substitutes its own parameter when a level declaring none comes first")
    func eachArgumentSubstitutesItsOwnParameter() async throws {
        let integerType = try await demangleAsNode("Si", isType: true)
        let stringType = try await demangleAsNode("SS", isType: true)

        let resolved = try await resolvedUnderlyingType(ofDeclarationNamed: "makePair", argumentListsByLevel: [[], [integerType], [stringType]])

        #expect(resolved == "\(Self.moduleName).ProbePair<Swift.Int, Swift.String>")
    }
}
