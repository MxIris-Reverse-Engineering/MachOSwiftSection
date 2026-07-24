import MachOSwiftSection
import Demangling
import OrderedCollections
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

/// Finds the implementation symbol whose demangled `.class` node matches
/// `typeNode`'s class node, skipping already-visited nodes.
///
/// Lifted out of `SwiftDump`'s `ClassDumper.demangledSymbol(for:typeNode:…)`
/// so the declaration model can resolve method-override symbols during indexing
/// (`TypeDefinition.index`) without depending on the dump layer. It is purely a
/// symbol-table matcher — no rendering — so it belongs with the model rather
/// than the renderer.
package func demangledOverrideSymbol<MachO: MachOSwiftSectionRepresentableWithCache>(
    for symbols: Symbols,
    typeNode: Node,
    visitedNodes: borrowing OrderedSet<NodeReference> = [],
    in machO: MachO
) -> DemangledSymbol? {
    guard let typeClassNode = typeNode.first(of: .class) else { return nil }
    for symbol in symbols {
        if let node = SymbolIndexStore.shared.demangledNodeReference(for: symbol, in: machO),
           let classNode = node.first(of: .class),
           classNode.structurallyEquals(typeClassNode),
           !visitedNodes.contains(node) {
            return .init(symbol: symbol, demangledNode: node)
        }
    }
    return nil
}
