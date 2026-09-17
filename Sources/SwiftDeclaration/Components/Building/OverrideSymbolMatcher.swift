import MachOSwiftSection
import Demangling
import OrderedCollections
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

/// Finds the implementation symbol declared in `typeNode`'s class, skipping
/// already-visited nodes.
///
/// The match is on the member's DIRECT declaration context. Matching on
/// `first(of: .class)` — the first class node anywhere in the tree — accepts
/// members of NESTED types as members of the enclosing class
/// (`GraphHost.Data.graph.modify` reports `GraphHost`), which under identical
/// code folding is how a vtable slot acquires a name belonging to something
/// else entirely.
///
/// `visitedNodes` is keyed structurally: `demangledNodeReference(for:)` can
/// hand back references from different stores, and under store-identity
/// equality the "already claimed this symbol" guard would stop firing across
/// them, letting two descriptors bind the same implementation.
///
/// Lifted out of `SwiftDump`'s `ClassDumper.demangledSymbol(for:typeNode:…)`
/// so the declaration model can resolve method-override symbols during indexing
/// (`TypeDefinition.index`) without depending on the dump layer. It is purely a
/// symbol-table matcher — no rendering — so it belongs with the model rather
/// than the renderer.
/// The structural key `DefinitionBuilder` joins descriptor-side symbols to
/// member-side symbols on.
///
/// An async method's descriptor `implementation` points at its `Tu`
/// async-function-pointer constant, whose demangled tree carries a leading
/// `.asyncFunctionPointer` marker child the member symbol's tree does not —
/// keyed verbatim, the two trees never match structurally, so async members
/// never joined (no vtable comment, no `override` keyword and, since evolution
/// proposal 0006, a false `final`). Strip the marker so the key takes the
/// member form; every other tree keys as-is.
package func memberJoinKey<MachO: MachOSwiftSectionRepresentableWithCache>(
    for node: NodeReference,
    in machO: MachO
) -> StructuralNodeReferenceKey {
    if node.children.first?.kind == .asyncFunctionPointer, let entityNode = node.children.second {
        let strippedTree = Node.create(kind: .global, child: entityNode.materialize())
        return StructuralNodeReferenceKey(InternedNodeReferenceCache.shared.reference(interning: strippedTree, in: machO))
    }
    return StructuralNodeReferenceKey(node)
}

package func demangledOverrideSymbol<MachO: MachOSwiftSectionRepresentableWithCache>(
    for symbols: Symbols,
    typeNode: Node,
    visitedNodes: borrowing OrderedSet<StructuralNodeReferenceKey> = [],
    in machO: MachO
) -> DemangledSymbol? {
    guard let typeClassNode = typeNode.first(of: .class) else { return nil }
    for symbol in symbols {
        if let node = SymbolIndexStore.shared.demangledNodeReference(for: symbol, in: machO),
           let declarationContextNode = node.declarationContextNode,
           declarationContextNode.structurallyEquals(typeClassNode),
           !visitedNodes.contains(StructuralNodeReferenceKey(node)) {
            return .init(symbol: symbol, demangledNode: node)
        }
    }
    return nil
}
