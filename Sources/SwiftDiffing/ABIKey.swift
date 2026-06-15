import Demangling

/// A stable, version-independent identity for a Swift declaration, derived by
/// *remangling* its demangled `Node` back into a canonical symbol string.
///
/// Swift name mangling encodes a declaration's full ABI contract — module,
/// parent context, name, parameter/return types, throws/async, generic
/// signature. Two builds where a declaration's `ABIKey` is unchanged carry the
/// same ABI for that declaration; a changed key marks an ABI change. Remangling
/// is total over the declarations we key (every member carries a `Node`), so no
/// Mach-O is needed — keys are pure functions of the indexed model.
///
/// Note on the two roles: `MemberRecord` uses `ABIKey` both as a matching
/// *identity* and as a change-detection *payload*, and for entities with no
/// symbol (stored fields, enum cases) it carries a namespaced `.printed` source
/// key rather than a true mangled identity. So `ABIKey` is best read as "the
/// canonical comparison token for a declaration", of which the remangled symbol
/// is the preferred form. (TODO(P2): consider splitting identity vs payload key
/// types if the overload becomes confusing.)
public enum ABIKey: Hashable, Sendable {
    /// The remangled symbol string — the preferred, signature-complete form.
    case mangled(String)

    /// A fallback rendering used when a node cannot be remangled
    /// (`mangleAsString` throws). It is prefixed with the node's root kind and
    /// printed with bound-generic arguments retained, so that `struct Foo` vs
    /// `class Foo` and `Box<Int>` vs `Box<String>` stay distinct even on the
    /// fallback path.
    case printed(String)

    /// Key a declaration node directly. Use for member *declaration* nodes
    /// (`FunctionDefinition.node`, `VariableDefinition.node`,
    /// `SubscriptDefinition.node`) which are rooted at `.global` / `.function`
    /// and remangle as-is.
    public static func make(for node: Node) -> ABIKey {
        // `canMangle` is literally `(try? mangleAsString) != nil`, so a single
        // `try?` decides the branch and remangles exactly once.
        if let mangled = try? mangleAsString(node) {
            return .mangled(mangled)
        }
        return .printed(fallbackString(for: node))
    }

    /// Key a node that may be wrapped in a `.type` envelope — name nodes
    /// (`TypeName.node`, `ProtocolName.node`) and field type nodes
    /// (`FieldDefinition.typeNode`). The `.type` wrapper is stripped first
    /// because `mangleAsString` rejects some `.type`-rooted trees.
    public static func makeUnwrappingType(for node: Node) -> ABIKey {
        make(for: unwrapType(node))
    }

    /// A stable string projection for deterministic sorting of diff output.
    /// The case tag keeps mangled and printed keys from interleaving.
    public var sortKey: String {
        switch self {
        case .mangled(let value): return "0:" + value
        case .printed(let value): return "1:" + value
        }
    }

    /// Strip a single `.type` envelope so the inner nominal node can remangle.
    /// A no-op when the node is not `.type`-rooted.
    static func unwrapType(_ node: Node) -> Node {
        node.kind == .type ? (node.children.first ?? node) : node
    }

    /// The injective fallback rendering: root kind + a print that retains
    /// bound-generic arguments (`.interfaceBuilderOnly` is
    /// `.interfaceTypeBuilderOnly` without `.removeBoundGeneric`).
    private static func fallbackString(for node: Node) -> String {
        "\(node.kind):\(node.print(using: .interfaceBuilderOnly))"
    }
}
