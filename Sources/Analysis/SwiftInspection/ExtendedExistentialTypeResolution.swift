@_spi(Internals) import Demangling
import MachOSwiftSection

/// The existential type a constrained existential in runtime metadata stands
/// for (evolution proposal `existential-any`).
///
/// A field record, an associated type witness or any other runtime mangled name
/// spells `any Boxed<Int>` as a `symbolicExtendedExistentialType`: a symbolic
/// reference to an extended existential type shape, generalized over the
/// shape's own generic parameters, plus the arguments that instantiate it.
/// IRGen generalizes the shape so that `any Boxed<Int>` and
/// `any Boxed<String>` share one:
///
/// ```
/// symbolicExtendedExistentialType
///   nonUniqueExtendedExistentialTypeShapeSymbolicReference
///     constrainedExistential            any Boxed<Self.Wrapped == τ_0_0>
///   typeList                            [Swift.Int]
/// ```
///
/// `SymbolicDemangler` resolves the reference to the shape's existential type;
/// a printer that read only the argument list printed the field as `Swift.Int`.
/// Substituting the arguments into the shape gives the tree a symbol mangling
/// spells for the same type — the property's getter names it with a
/// `constrainedExistential` directly — so every consumer reads one shape.
package enum ExtendedExistentialTypeResolution {
    /// The existential type `node`, a `symbolicExtendedExistentialType`, stands
    /// for: its shape's existential type with the generalization arguments
    /// substituted. `nil` for any other node, and for a shape reference that was
    /// not resolved to a type.
    package static func existentialType(of node: Node) -> Node? {
        guard node.kind == .symbolicExtendedExistentialType,
              let shape = node.children.first,
              shape.kind == .uniqueExtendedExistentialTypeShapeSymbolicReference
              || shape.kind == .nonUniqueExtendedExistentialTypeShapeSymbolicReference,
              shape.children.count == 1,
              let shapeExistentialType = shape.children.first
        else { return nil }
        // The generalization signature declares a single depth, so its
        // parameters are `τ_0_0`, `τ_0_1`, … in argument order. `Self` in the
        // shape's requirements is a `constrainedExistentialSelf`, which no
        // substitution touches.
        let generalizationArguments: [Node] = node.children.at(1).map { Array($0.children) } ?? []
        guard !generalizationArguments.isEmpty else { return shapeExistentialType }
        return GenericArgumentBinding(argumentsByDepth: [generalizationArguments]).substituting(in: shapeExistentialType)
    }

    /// `node` with every resolved `symbolicExtendedExistentialType` replaced by
    /// the existential type it stands for. A subtree holding none comes back as
    /// the same instance.
    package static func resolvingExtendedExistentialTypes(in node: Node) -> Node {
        var rewrittenNodes: [ObjectIdentifier: Node] = [:]
        return resolve(node, rewrittenNodes: &rewrittenNodes)
    }

    // A demangled tree is a DAG — every back-reference to a substitution is the
    // same instance — so the walk is memoized by identity and stays linear in
    // the unique nodes.
    private static func resolve(_ node: Node, rewrittenNodes: inout [ObjectIdentifier: Node]) -> Node {
        if let rewrittenNode = rewrittenNodes[ObjectIdentifier(node)] {
            return rewrittenNode
        }
        // Children first: a generalization argument may be a constrained
        // existential itself (`any Boxed<any Sequence<Int>>`).
        var rewrittenChildren: [Node] = []
        rewrittenChildren.reserveCapacity(node.children.count)
        var hasRewrittenChild = false
        for child in node.children {
            let rewrittenChild = resolve(child, rewrittenNodes: &rewrittenNodes)
            hasRewrittenChild = hasRewrittenChild || rewrittenChild !== child
            rewrittenChildren.append(rewrittenChild)
        }
        // A node's children and contents are mutually exclusive, so a node
        // rebuilt from its children alone loses nothing.
        var rewrittenNode = hasRewrittenChild ? Node.createTransient(kind: node.kind, children: rewrittenChildren) : node
        if let existentialType = existentialType(of: rewrittenNode) {
            rewrittenNode = existentialType
        }
        rewrittenNodes[ObjectIdentifier(node)] = rewrittenNode
        return rewrittenNode
    }
}

extension MangledName {
    /// Whether the name holds a symbolic reference to an extended existential
    /// type shape — the only names whose demangling has a
    /// `symbolicExtendedExistentialType` to resolve. Read off the reference
    /// kinds, so every other name skips the walk.
    var refersToExtendedExistentialTypeShape: Bool {
        lookupElements.contains { lookup in
            guard case .relative(let reference) = lookup.reference else { return false }
            return reference.kind == SymbolicManglingIndex.Kind.uniqueExtendedExistentialTypeShape.rawValue
                || reference.kind == SymbolicManglingIndex.Kind.nonUniqueExtendedExistentialTypeShape.rawValue
        }
    }
}
