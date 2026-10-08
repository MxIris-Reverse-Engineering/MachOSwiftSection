import Demangling

extension Node {
    /// The same tree with every `dependentAssociatedTypeRef` reduced to its
    /// identifier: `A.[Walkable]Next.[Walkable]Next` becomes `A.Next.Next`.
    ///
    /// A generic requirement's mangling qualifies each associated type with
    /// the protocol that declares it, and the upstream `NodePrinter` spells
    /// that qualification out — `A.Probe.Walkable.Next` — which is not
    /// Swift. The project's own type printer already drops it
    /// (`DependentGenericNodePrintable.printDependentAssociatedTypeRef` in
    /// `SwiftPrinting`); this is the same reduction for a tree that is
    /// printed through the upstream printer instead, such as the argument of
    /// an opaque type's primary-associated-type sugar.
    ///
    /// Unchanged subtrees are shared, not copied: `Node.Rewriter` rebuilds
    /// only the parents of a node it replaced.
    package func strippingAssociatedTypeProtocolQualifiers() -> Node {
        AssociatedTypeProtocolQualifierStripper().rewrite(self)
    }
}

private final class AssociatedTypeProtocolQualifierStripper: Node.Rewriter {
    override func visit(_ node: Node) -> Node {
        guard node.isKind(of: .dependentAssociatedTypeRef), node.children.count > 1 else { return node }
        return NodeBuilder(node).removingChild(at: 1)
    }
}
