import Demangling

/// A generic parameter's position in a generic signature: its declaration
/// `depth` (0 = the type's own parameters, 1+ = an enclosing generic context)
/// and `index` within that depth.
struct GenericParameterKey: Hashable {
    let depth: UInt64
    let index: UInt64
}

/// Maps a generic type's `(depth, index)` parameters to the concrete arguments
/// of a specific instantiation, enabling purely *syntactic* substitution of
/// `dependentGenericParamType` nodes in a field's demangled type tree — no
/// metadata accessor, no protocol witness tables, no runtime.
///
/// Built from a `boundGeneric*` node: the node carries its source-level
/// arguments in a `.typeList`, ordered by declaration. A generic type's own
/// parameters are at depth 0, so the i-th argument maps to the parameter
/// `(depth: 0, index: i)` — the exact `(depth, index)` the field records'
/// `dependentGenericParamType` nodes reference.
///
/// Scope: depth-0 parameters, in three argument kinds:
/// - plain **type** arguments (`Foo<Int>`),
/// - **value** arguments (`Foo<5>`) — bound as `.integer` / `.negativeInteger`
///   nodes and consumed by the resolver's fixed-array formulas,
/// - **pack** arguments (`Foo<Pack{Int, String}>`) — bound as flat `.pack`
///   nodes. Substitution expands concrete pack expansions in place: a tuple
///   element `repeat each T` flattens into the pack's elements (with the
///   runtime's single-unlabeled-element tuple collapse), and a pack literal
///   containing an expansion (the `Foo<repeat each T>` forwarding shape)
///   flattens into a concrete pack.
///
/// An argument that cannot be modelled (a pack that itself still contains an
/// unexpanded expansion) degrades the whole environment to `.empty` so the
/// type's fields stay `.unknown` rather than risk a positional misalignment —
/// matching the engine's existing per-field degradation.
struct GenericArgumentEnvironment {
    let substitutions: [GenericParameterKey: Node]

    static let empty = GenericArgumentEnvironment(substitutions: [:])

    var isEmpty: Bool { substitutions.isEmpty }

    /// Derives the depth-0 substitution map from a `boundGeneric*` node, or
    /// `.empty` for a non-generic node or one whose arguments cannot all be
    /// modelled.
    static func make(forBoundGenericNode node: Node) -> GenericArgumentEnvironment {
        // Tolerate a leading `.type` wrapper: a freshly demangled type node is
        // `.type`-wrapped, whereas the resolver's dispatch unwraps it first —
        // both must build the same environment.
        let boundGenericNode = (node.kind == .type ? node.firstChild : node) ?? node
        guard isBoundGenericKind(boundGenericNode.kind), let typeList = directTypeList(of: boundGenericNode) else {
            return .empty
        }
        return make(forDepthZeroTypeArguments: Array(typeList.children))
    }

    /// Builds the depth-0 substitution map directly from a list of concrete
    /// arguments (ordered by declaration), as supplied by a caller that holds a
    /// generic type descriptor and its instantiation arguments rather than a
    /// `boundGeneric*` node. Each argument must be a `.type`-wrapped type,
    /// value, or flat pack node; anything else degrades the whole environment
    /// to `.empty`, matching `make(forBoundGenericNode:)`. An empty argument
    /// list yields `.empty` (nothing to substitute).
    static func make(forDepthZeroTypeArguments arguments: [Node]) -> GenericArgumentEnvironment {
        guard !arguments.isEmpty else { return .empty }
        var substitutions: [GenericParameterKey: Node] = [:]
        for (index, argument) in arguments.enumerated() {
            // Bail on any argument that cannot be substituted positionally:
            // those occupy parameter ordinals too, so degrade the whole
            // instantiation rather than misindex.
            guard let inner = substitutableInnerArgument(of: argument) else { return .empty }
            substitutions[GenericParameterKey(depth: 0, index: UInt64(index))] = inner
        }
        return GenericArgumentEnvironment(substitutions: substitutions)
    }

    /// Deep-rewrites `node`, replacing every `dependentGenericParamType` whose
    /// `(depth, index)` is bound in this environment with the corresponding
    /// concrete argument, and expanding concrete pack expansions inside tuple
    /// and pack nodes along the way. Parameters not in the map (e.g. depth > 0)
    /// are left intact, so they later degrade to `.unknown` as before.
    func substituting(in node: Node) -> Node {
        guard !isEmpty else { return node }
        return substitute(node)
    }

    // MARK: - Top-down substitution

    /// The substitution recursion is hand-rolled and top-down (rather than a
    /// bottom-up `Node.Rewriter`) because pack expansion is context-sensitive:
    /// inside expansion instance `i`, a pack-bound parameter reference resolves
    /// to the pack's `i`-th element, not to the whole pack. A bottom-up pass
    /// would have already replaced the pattern's references with whole `.pack`
    /// nodes, making them indistinguishable from literal pack arguments in
    /// nested shapes like `(repeat Pair<each T>)`.
    private func substitute(_ node: Node) -> Node {
        switch node.kind {
        case .dependentGenericParamType:
            return substitutionValue(for: node) ?? node
        case .tuple:
            return substituteTuple(node)
        case .pack:
            return substitutePack(node)
        default:
            return substitutingChildren(of: node)
        }
    }

    private func substitutionValue(for parameterNode: Node) -> Node? {
        guard
            let depth = parameterNode.firstChild?.index,
            let index = parameterNode.children.at(1)?.index
        else {
            return nil
        }
        return substitutions[GenericParameterKey(depth: depth, index: index)]
    }

    private func substitutingChildren(of node: Node) -> Node {
        var rewrittenChildren: [Node] = []
        rewrittenChildren.reserveCapacity(node.children.count)
        var hasChildrenChanged = false
        for child in node.children {
            let rewrittenChild = substitute(child)
            if rewrittenChild !== child { hasChildrenChanged = true }
            rewrittenChildren.append(rewrittenChild)
        }
        guard hasChildrenChanged else { return node }
        return Node.create(kind: node.kind, contents: node.contents, children: rewrittenChildren)
    }

    /// Substitutes a tuple node, flattening any element that is a concrete
    /// pack expansion. Mirrors the type system's substitution semantics:
    /// `(repeat each T)` with `T = Pack{Int, Bool}` becomes `(Int, Bool)`; an
    /// expansion over an empty pack vanishes; and a tuple that flattens to
    /// exactly one unlabeled element collapses to that element (one-element
    /// unlabeled tuples do not exist — the runtime returns the element's
    /// metadata for them). An expansion whose count is not concretely bound is
    /// left in place so the resolver degrades that field.
    private func substituteTuple(_ tupleNode: Node) -> Node {
        let containsExpansionElement = tupleNode.children.contains { packExpansionOfTupleElement($0) != nil }
        guard containsExpansionElement else { return substitutingChildren(of: tupleNode) }

        var flattenedElements: [Node] = []
        var hasAnyLabel = false
        var hasUnexpandedExpansion = false
        for element in tupleNode.children {
            if element.kind == .tupleElement, element.children.contains(where: { $0.kind == .tupleElementName }) {
                hasAnyLabel = true
            }
            guard let expansion = packExpansionOfTupleElement(element) else {
                flattenedElements.append(substitute(element))
                continue
            }
            guard let instances = expandedInstances(of: expansion) else {
                // Not concretely expandable here (unbound count, or a pack
                // value too short) — keep the element untouched so the
                // resolver reports `genericParameterUnsubstituted`.
                flattenedElements.append(element)
                hasUnexpandedExpansion = true
                continue
            }
            for instance in instances {
                flattenedElements.append(Node.create(kind: .tupleElement, child: Node.create(kind: .type, child: instance)))
            }
        }

        // The single-unlabeled-element collapse. Only reachable through an
        // actual expansion (written source cannot form a one-element tuple).
        if
            !hasAnyLabel,
            !hasUnexpandedExpansion,
            flattenedElements.count == 1,
            let onlyElementType = flattenedElements[0].children.first(where: { $0.kind == .type }),
            let onlyElementInner = onlyElementType.firstChild
        {
            return onlyElementInner
        }
        return Node.create(kind: .tuple, children: flattenedElements)
    }

    /// Substitutes a pack literal, splicing any expansion child into its
    /// concrete instances — the `Foo<repeat each T>` forwarding shape, whose
    /// argument pack is `Pack{PackExpansion(…)}` and must flatten to
    /// `Pack{Int, Bool}` before it can bind `Foo`'s own pack parameter.
    private func substitutePack(_ packNode: Node) -> Node {
        let containsExpansionChild = packNode.children.contains { packExpansionOfTypeWrappedChild($0) != nil }
        guard containsExpansionChild else { return substitutingChildren(of: packNode) }

        var flattenedChildren: [Node] = []
        for child in packNode.children {
            guard let expansion = packExpansionOfTypeWrappedChild(child) else {
                flattenedChildren.append(substitute(child))
                continue
            }
            guard let instances = expandedInstances(of: expansion) else {
                // Leave the whole pack untouched: a partially flattened pack
                // would silently shift the remaining argument positions.
                return packNode
            }
            for instance in instances {
                flattenedChildren.append(Node.create(kind: .type, child: instance))
            }
        }
        return Node.create(kind: .pack, children: flattenedChildren)
    }

    /// Expands one `packExpansion` node into its per-element pattern
    /// instances, or `nil` when the expansion is not concretely bound in this
    /// environment. The expansion's children are the (bare, unwrapped) pattern
    /// and count types; the count must substitute to a concrete `.pack`, and
    /// instance `i` substitutes the pattern with every pack-bound parameter
    /// mapped to its `i`-th element.
    private func expandedInstances(of expansion: Node) -> [Node]? {
        guard
            expansion.children.count == 2,
            let pattern = expansion.firstChild,
            let count = expansion.children.at(1)
        else {
            return nil
        }
        let substitutedCount = substitute(count)
        guard substitutedCount.kind == .pack else { return nil }
        var instances: [Node] = []
        instances.reserveCapacity(substitutedCount.children.count)
        for elementIndex in 0 ..< substitutedCount.children.count {
            guard let elementEnvironment = packElementEnvironment(atIndex: elementIndex) else { return nil }
            instances.append(elementEnvironment.substitute(pattern))
        }
        return instances
    }

    /// This environment with every pack-bound parameter narrowed to its
    /// `index`-th element — the substitution context inside expansion instance
    /// `index`. Non-pack bindings pass through unchanged. Returns `nil` when a
    /// pack value does not cover `index` (a malformed tree; degrade rather
    /// than misindex).
    private func packElementEnvironment(atIndex index: Int) -> GenericArgumentEnvironment? {
        var elementSubstitutions = substitutions
        for (key, value) in substitutions where value.kind == .pack {
            guard
                let elementType = value.children.at(index),
                elementType.kind == .type,
                let elementInner = elementType.firstChild
            else {
                return nil
            }
            elementSubstitutions[key] = elementInner
        }
        return GenericArgumentEnvironment(substitutions: elementSubstitutions)
    }

    // MARK: - Node shape helpers

    private static func isBoundGenericKind(_ kind: Node.Kind) -> Bool {
        switch kind {
        case .boundGenericStructure, .boundGenericEnum, .boundGenericClass,
             .boundGenericOtherNominalType, .boundGenericTypeAlias, .boundGenericProtocol:
            return true
        default:
            return false
        }
    }

    /// The direct `.typeList` child of a bound-generic node (its argument list),
    /// `nil` if absent. Scans direct children rather than a deep search so a
    /// nested generic argument's own `.typeList` is never picked up.
    private static func directTypeList(of node: Node) -> Node? {
        node.children.first(where: { $0.kind == .typeList })
    }

    /// The unwrapped inner node of a `.type`-wrapped argument, or `nil` if the
    /// argument cannot serve as a positional substitution value. Plain types,
    /// value arguments (`.integer` / `.negativeInteger`), and *flat* packs are
    /// accepted; a pack still containing an expansion (an unresolved forwarding
    /// shape) is not. The inner is returned unwrapped so a substitution leaves
    /// exactly one `.type` wrapper (the one already surrounding the replaced
    /// parameter).
    private static func substitutableInnerArgument(of argument: Node) -> Node? {
        guard argument.kind == .type, let inner = argument.firstChild else { return nil }
        switch inner.kind {
        case .packExpansion, .typeList:
            return nil
        case .pack:
            let isFlat = inner.children.allSatisfy { child in
                child.kind == .type && child.firstChild?.kind != .packExpansion
            }
            return isFlat ? inner : nil
        default:
            return inner
        }
    }

    /// The `.packExpansion` node of a `.tupleElement` whose type is an
    /// expansion, `nil` otherwise.
    private func packExpansionOfTupleElement(_ element: Node) -> Node? {
        guard element.kind == .tupleElement else { return nil }
        guard let typeNode = element.children.first(where: { $0.kind == .type }) else { return nil }
        guard let inner = typeNode.firstChild, inner.kind == .packExpansion else { return nil }
        return inner
    }

    /// The `.packExpansion` node of a `.type`-wrapped pack-literal child that
    /// is an expansion, `nil` otherwise.
    private func packExpansionOfTypeWrappedChild(_ child: Node) -> Node? {
        guard child.kind == .type, let inner = child.firstChild, inner.kind == .packExpansion else { return nil }
        return inner
    }
}
