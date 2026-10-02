@_spi(Internals) import Demangling

/// The arguments one instantiation of a generic type binds its parameters to,
/// one list per depth (evolution proposal `offline-generic-specialization`).
///
/// A generic parameter is identified by its `(depth, index)` — the pair every
/// mangled reference to it carries (`τ_1_0`, printed `A1`) — and a depth is a
/// context that declares parameters: `Outer<Int>.Inner<String>` binds depth 0
/// to `[Int]` and depth 1 to `[String]`, while `Outer<Int>.Middle.Inner<String>`
/// binds the same two depths, because `Middle` declares none. That is exactly
/// how an instantiated type node spells its arguments, one `TypeList` on each
/// level that declares parameters, so the two convert into each other.
///
/// The arguments are demangled type nodes, never metadata: an offline reader
/// has nothing else, and a node is what a renderer substitutes into a field's
/// type and what the static layout engine lays out.
public struct GenericArgumentBinding: Sendable, Hashable {
    /// The arguments of each depth, outermost first, in declaration order —
    /// the argument `argumentsByDepth[depth][index]` is what the parameter
    /// `(depth, index)` stands for. Every argument is `.type`-wrapped.
    public let argumentsByDepth: [[Node]]

    public init(argumentsByDepth: [[Node]]) {
        self.argumentsByDepth = argumentsByDepth.map { arguments in
            arguments.map(Self.typeWrapped)
        }
    }

    /// The binding an instantiated type node spells: the argument list of
    /// every level that declares parameters, outermost first. `nil` for a
    /// node with no instantiated level (a non-generic type, or an unbound
    /// generic one).
    public init?(instantiatedTypeNode: Node) {
        let argumentLists = Self.argumentListsByLevel(ofInstantiatedTypeNode: instantiatedTypeNode)
        guard !argumentLists.isEmpty else { return nil }
        self.init(argumentsByDepth: argumentLists)
    }

    public var isEmpty: Bool {
        argumentsByDepth.allSatisfy(\.isEmpty)
    }

    /// The argument the parameter `(depth, index)` stands for.
    public func argument(depth: Int, index: Int) -> Node? {
        guard argumentsByDepth.indices.contains(depth), argumentsByDepth[depth].indices.contains(index) else { return nil }
        return argumentsByDepth[depth][index]
    }

    /// Every argument in the order of the generic context's cumulative
    /// parameter list.
    public var flattenedArguments: [Node] {
        argumentsByDepth.flatMap { $0 }
    }

    /// `node` with every generic parameter this binding binds replaced by its
    /// argument, for display: a field's `A?` becomes `Swift.Int?`, and
    /// `A.Element` becomes `[Swift.Int].Element` — still a dependent member,
    /// which a caller that can read conformance records projects further. A
    /// parameter the binding does not cover stays as it is.
    ///
    /// Unlike the static layout engine's substitution this one reaches into a
    /// metatype too: `A.Type` reads `Swift.Int.Type`, which is what it is. The
    /// layout engine leaves a metatype's instance alone because the metatype's
    /// storage depends on the instance's syntactic kind, not on what it binds
    /// to — a concern of layout, not of naming.
    public func substituting(in node: Node) -> Node {
        guard !isEmpty else { return node }
        var rewrittenNodes: [ObjectIdentifier: Node] = [:]
        return substitute(node, rewrittenNodes: &rewrittenNodes)
    }

    // The tree a demangler hands back is a DAG — every back-reference to a
    // substitution is the same instance — so the walk is memoized by identity
    // and stays linear in the unique nodes. A subtree with nothing to
    // substitute comes back as the same instance.
    private func substitute(_ node: Node, rewrittenNodes: inout [ObjectIdentifier: Node]) -> Node {
        if let rewrittenNode = rewrittenNodes[ObjectIdentifier(node)] {
            return rewrittenNode
        }
        let rewrittenNode: Node
        if node.kind == .dependentGenericParamType, let argument = boundArgument(of: node) {
            // The parameter node sits inside a `.type` wrapper already, so the
            // argument's own wrapper is dropped to leave exactly one.
            rewrittenNode = argument.firstChild ?? argument
        } else {
            var rewrittenChildren: [Node] = []
            rewrittenChildren.reserveCapacity(node.children.count)
            var hasRewrittenChild = false
            for child in node.children {
                let rewrittenChild = substitute(child, rewrittenNodes: &rewrittenNodes)
                hasRewrittenChild = hasRewrittenChild || rewrittenChild !== child
                rewrittenChildren.append(rewrittenChild)
            }
            // A node's children and contents are mutually exclusive, so a node
            // rebuilt from its children alone loses nothing.
            rewrittenNode = hasRewrittenChild ? Node.createTransient(kind: node.kind, children: rewrittenChildren) : node
        }
        rewrittenNodes[ObjectIdentifier(node)] = rewrittenNode
        return rewrittenNode
    }

    private func boundArgument(of parameterNode: Node) -> Node? {
        guard parameterNode.children.count == 2,
              let depth = parameterNode.children[0].index,
              let index = parameterNode.children[1].index
        else { return nil }
        return argument(depth: Int(depth), index: Int(index))
    }

    private static func typeWrapped(_ node: Node) -> Node {
        node.kind == .type ? node : Node.createTransient(kind: .type, child: node)
    }
}

// MARK: - Reading an instantiated type node

extension GenericArgumentBinding {
    /// The argument lists an instantiated type node carries, one per level
    /// that declares parameters, outermost first — so the i-th list is depth
    /// i's arguments.
    ///
    /// The demangler wraps exactly the levels that declare parameters in a
    /// `boundGeneric*` node; a level that declares none (`Middle` in
    /// `Outer<Int>.Middle.Inner<String>`) is a plain nominal. A type declared
    /// in an extension has the extension as its context, and the outer
    /// arguments ride the extension's extended type: `Outer<Int>.Inner<String>`
    /// for an `Inner` in `extension Outer where …` is `Inner` under
    /// `Extension(<module>, Outer<Int>, <signature>)`. The walk goes through
    /// it; a module, a function or any other context ends it, since no
    /// instantiated level can sit beyond one.
    public static func argumentListsByLevel(ofInstantiatedTypeNode node: Node) -> [[Node]] {
        var argumentListsInnermostFirst: [[Node]] = []
        var currentNode: Node? = node
        while let cursor = currentNode {
            let unwrapped = (cursor.kind == .type ? cursor.firstChild : cursor) ?? cursor
            switch unwrapped.kind {
            case .boundGenericStructure, .boundGenericEnum, .boundGenericClass,
                 .boundGenericOtherNominalType, .boundGenericTypeAlias, .boundGenericProtocol:
                // The direct `TypeList` child only: a nested generic argument's
                // own list must not be picked up.
                if let typeList = unwrapped.children.first(where: { $0.kind == .typeList }), !typeList.children.isEmpty {
                    argumentListsInnermostFirst.append(Array(typeList.children))
                }
                currentNode = unwrapped.firstChild
            case .structure, .enum, .class, .otherNominalType, .typeAlias, .protocol:
                // A nominal's first child is its declaration context.
                currentNode = unwrapped.firstChild
            case .extension:
                // `Extension(<module>, <extended type>, <signature>?)`.
                currentNode = unwrapped.children.count > 1 ? unwrapped.children[1] : nil
            default:
                currentNode = nil
            }
        }
        return argumentListsInnermostFirst.reversed()
    }
}
