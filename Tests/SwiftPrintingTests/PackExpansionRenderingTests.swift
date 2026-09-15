@_spi(Support) @testable import SwiftPrinting
import Foundation
import Demangling
import Testing

/// Pins the `each` / `repeat` spelling of parameter packs.
///
/// Every mangled name below was produced by compiling the Swift source quoted
/// beside it, so the expectations are the source's own spelling rather than a
/// reading of the mangling. Demangling is pure string work, so none of those
/// modules has to exist to run this.
///
/// What makes packs worth pinning: `each` appears nowhere at a use site. A
/// parameter's pack-ness lives on the generic signature
/// (`dependentGenericParamPackMarker`) and on the expansion's count type, and a
/// reference to a pack is byte-identical to a reference to an ordinary
/// parameter. Every case here rendered as uncompilable Swift at some point
/// during this batch, each for a different reason.
@Suite
struct PackExpansionRenderingTests {
    private func rendered(_ mangled: String) async throws -> String {
        let node = try await demangleAsNode(mangled)
        var printer = FunctionNodePrinter(isOverride: false)
        return try await printer.printRoot(node).string
    }

    /// `public func acceptsAny<each A>(_: repeat (each A).Type) -> Bool`
    /// (top level, one pack, depth 0).
    ///
    /// The parenthesisation is not cosmetic: `each` binds tighter than a
    /// suffix, so `repeat each A.Type` is rejected by the compiler outright.
    @Test func topLevelPackFunction() async throws {
        let text = try await rendered("$s8packfunc6HolderO10acceptsAnyySbxmxQpRvzAA8StyleCtxRzlFZ")
        #expect(text.contains("<each A>"), "\(text)")
        #expect(text.contains("repeat (each A).Type"), "\(text)")
    }

    /// The same shape one level in — `Outer<T>.f<each A1>`.
    ///
    /// Regression for two stacked bugs that were invisible at depth 0, where
    /// every sample lived: `dependentGenericParamType`'s children are
    /// (depth, index) and were compared the other way round (harmless whenever
    /// depth == index), and the pack lookup used the parameter-count node's
    /// position instead of the depth the NAME had already resolved. The
    /// declaration printed `<A1>` beside its own `repeat (each A1)`.
    @Test func nestedPackFunctionKeepsEachOnItsDeclaration() async throws {
        let text = try await rendered("$s9packdepth5OuterV1fySbqd__mqd__QpRvd__AA8StyleCtxRd__lFZ")
        #expect(text.contains("<each A1>"), "\(text)")
        #expect(text.contains("repeat (each A1).Type"), "\(text)")
    }

    /// `struct Mixed<T, each U> { var x: (repeat (T, each U)) }` — a scalar and
    /// a pack under one expansion.
    ///
    /// Only `U` may take `each`. The expansion's count type (child 1) names it,
    /// which is what a type's field has to rely on: its type tree carries no
    /// signature, and it suffices because a generic type may declare at most
    /// one pack.
    @Test func scalarAndPackUnderOneExpansion() async throws {
        // A stored property's getter, so the type subtree goes to the type
        // printer directly — and that subtree carries no signature, which is
        // exactly the condition that makes the count type the only source.
        let node = try await demangleAsNode("$s9packmixed5MixedV1xx_q_tq_Qp_tvg")
        let typeNode = try #require(node.first(of: .type))
        var printer = TypeNodePrinter()
        let text = try await printer.printRoot(typeNode).string
        #expect(text == "(repeat (A, (each B)))", "\(text)")
    }

    /// `public func g<each A, each B>(_ x: (repeat (each A, each B)))` — two
    /// packs under one expansion, which only a function can declare.
    ///
    /// The count type names just one of them, so this is the case the count
    /// type alone cannot answer; the signature, printed by the same printer
    /// moments earlier, supplies the rest. Also pins that the implied
    /// same-shape requirement stays out of the `where` clause: source never
    /// writes it, upstream renders it `A.shape == B.shape` which is not Swift,
    /// and this printer had no case for it — so it emitted a `where` with
    /// nothing after it.
    @Test func twoPacksUnderOneExpansion() async throws {
        let text = try await rendered("$s8twopack21gyyx_q_txQp_t_tRvzRv_q_Rhzr0_lF")
        #expect(text.contains("<each A, each B>"), "\(text)")
        #expect(text.contains("(repeat ((each A), (each B)))"), "\(text)")
        #expect(!text.contains("where"), "\(text)")
    }
}
