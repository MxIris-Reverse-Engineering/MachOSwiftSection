import Demangling

/// A generic parameter's position in a generic signature: its declaration
/// `depth` (0 = the type's own parameters, 1+ = an enclosing generic context)
/// and `index` within that depth.
struct GenericParameterKey: Hashable {
    let depth: UInt64
    let index: UInt64
}

/// Maps a generic type's `(depth, index)` parameters to the concrete type
/// arguments of a specific instantiation, enabling purely *syntactic*
/// substitution of `dependentGenericParamType` nodes in a field's demangled
/// type tree — no metadata accessor, no protocol witness tables, no runtime.
///
/// Built from a `boundGeneric*` node: the node carries its source-level type
/// arguments in a `.typeList`, ordered by declaration. A generic type's own
/// parameters are at depth 0, so the i-th type argument maps to the parameter
/// `(depth: 0, index: i)` — the exact `(depth, index)` the field records'
/// `dependentGenericParamType` nodes reference.
///
/// Scope: depth-0 *type* parameters only. If any argument is a value or pack
/// argument (or otherwise not a plain substitutable type), the whole
/// environment degrades to `.empty` so the type's fields stay `.unknown` rather
/// than risk a positional misalignment — matching the engine's existing
/// per-field degradation for generics the static path does not model.
struct GenericArgumentEnvironment {
    let substitutions: [GenericParameterKey: Node]

    static let empty = GenericArgumentEnvironment(substitutions: [:])

    var isEmpty: Bool { substitutions.isEmpty }

    /// Derives the depth-0 substitution map from a `boundGeneric*` node, or
    /// `.empty` for a non-generic node or one whose arguments are not all plain
    /// substitutable types.
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
    /// type arguments (ordered by declaration), as supplied by a caller that
    /// holds a generic type descriptor and its instantiation arguments rather
    /// than a `boundGeneric*` node. Each argument must be a `.type`-wrapped
    /// type node; a value or pack argument degrades the whole environment to
    /// `.empty`, matching `make(forBoundGenericNode:)`. An empty argument list
    /// yields `.empty` (nothing to substitute).
    static func make(forDepthZeroTypeArguments arguments: [Node]) -> GenericArgumentEnvironment {
        guard !arguments.isEmpty else { return .empty }
        var substitutions: [GenericParameterKey: Node] = [:]
        for (index, argument) in arguments.enumerated() {
            // Bail on any non-type (value / pack) argument: those occupy
            // parameter ordinals too, and modelling them statically is out of
            // scope — degrade the whole instantiation rather than misindex.
            guard let inner = substitutableInnerType(of: argument) else { return .empty }
            substitutions[GenericParameterKey(depth: 0, index: UInt64(index))] = inner
        }
        return GenericArgumentEnvironment(substitutions: substitutions)
    }

    /// Deep-rewrites `node`, replacing every `dependentGenericParamType` whose
    /// `(depth, index)` is bound in this environment with the corresponding
    /// concrete argument. Parameters not in the map (e.g. depth > 0) are left
    /// intact, so they later degrade to `.unknown` as before.
    func substituting(in node: Node) -> Node {
        guard !isEmpty else { return node }
        return Substituter(environment: self).rewrite(node)
    }

    private final class Substituter: Node.Rewriter {
        private let environment: GenericArgumentEnvironment

        init(environment: GenericArgumentEnvironment) {
            self.environment = environment
            super.init()
        }

        override func visit(_ node: Node) -> Node {
            guard
                node.kind == .dependentGenericParamType,
                let depth = node.firstChild?.index,
                let index = node.children.at(1)?.index,
                let replacement = environment.substitutions[GenericParameterKey(depth: depth, index: index)]
            else {
                return node
            }
            return replacement
        }
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

    /// The unwrapped inner type of a `.type`-wrapped argument, or `nil` if the
    /// argument is not a plain substitutable type (a value or pack argument).
    /// The inner is returned unwrapped so a substitution leaves exactly one
    /// `.type` wrapper (the one already surrounding the replaced parameter).
    private static func substitutableInnerType(of argument: Node) -> Node? {
        guard argument.kind == .type, let inner = argument.firstChild else { return nil }
        switch inner.kind {
        case .integer, .negativeInteger, .pack, .packExpansion, .typeList:
            return nil
        default:
            return inner
        }
    }
}
