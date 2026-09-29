@_spi(Internals) import Demangling

// The type a member symbol is declared IN.
//
// `first(of: .class)` is NOT that question. It finds the first class node
// ANYWHERE in the tree, so a member of a NESTED type answers with the
// enclosing class and reads as that class's own member: the symbol
// `SwiftUI.GraphHost.Data.graph.modify` has the context chain
// `class GraphHost → struct Data`, and `first(of: .class)` happily returns
// `GraphHost`. Combined with identical code folding — where a whole address'
// worth of folded symbols is offered as candidates for one vtable slot — that
// is how three of `GraphHost`'s vtable methods came to print as coroutine
// resume functions of its nested `Data` struct.
//
// The declaration context is the DIRECT context of the tree's outermost
// entity, which is what the symbol index keys its member buckets on
// (`SymbolIndexStore.processThunkAttributeSymbol` extracts the same thing).

/// Node kinds that carry `(context, identifier, type)` — the shape whose first
/// child is the declaration context.
///
/// Accessor wrappers (`getter` / `setter` / `modify` / `read`) are deliberately
/// absent: their first child is the `variable` or `subscript` they wrap, not a
/// context, so they must be walked THROUGH rather than treated as the entity.
private let entityNodeKinds: Set<Node.Kind> = [
    .function,
    .variable,
    .subscript,
    .constructor,
    .allocator,
    .destructor,
    .deallocator,
]

extension NodeReference {
    /// The type this member symbol is declared in, or `nil` when the tree
    /// carries no entity whose context can be read.
    ///
    /// Searched breadth-first so the OUTERMOST entity wins: a function type
    /// nested in a member's signature (a closure parameter, say) is deeper
    /// than the member itself and must never be mistaken for it.
    public var declarationContextNode: NodeReference? {
        guard let entityNode = outermostEntityNode else { return nil }
        return entityNode.children.first.map { $0.unwrappingExtensionContext }
    }

    private var outermostEntityNode: NodeReference? {
        var queue: [NodeReference] = [self]
        var queueIndex = 0
        while queueIndex < queue.count {
            let candidate = queue[queueIndex]
            queueIndex += 1
            if entityNodeKinds.contains(candidate.kind) { return candidate }
            queue.append(contentsOf: candidate.children)
        }
        return nil
    }

    /// An `extension` context stands for the type it extends: the extension
    /// node's layout is `extension(module, extendedType, ?genericSignature)`,
    /// so the extended type is the second child. Any other node is itself.
    private var unwrappingExtensionContext: NodeReference {
        guard kind == .extension, let extendedType = children.second else { return self }
        return extendedType
    }
}
