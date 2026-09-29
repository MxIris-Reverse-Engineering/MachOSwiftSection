import MemberwiseInit
import Semantic
import Demangling

@MemberwiseInit(.public)
public struct TypeName: DefinitionName, Hashable, Sendable {
    public let node: NodeReference
    public let kind: TypeKind

    @SemanticStringBuilder
    public func print() -> SemanticString {
        switch kind {
        case .enum:
            TypeDeclaration(kind: .enum, name)
        case .struct:
            TypeDeclaration(kind: .struct, name)
        case .class:
            TypeDeclaration(kind: .class, name)
        }
    }
}

extension TypeName {
    public var extensionName: ExtensionName {
        ExtensionName(node: node, kind: .type(kind))
    }
}

// MARK: - Structural Hashable

// `NodeReference`'s intrinsic `Hashable` is store-identity based, which
// would split structurally equal names minted into different stores.
// Names key dictionaries by the node's STRUCTURE (matching the historical
// `node: Node` semantics), so equality and hashing walk the tree.
//
// `kind` deliberately takes no part. The node already identifies the type;
// `kind` is derived information whose derivation differs by producer — the
// descriptor's own kind on one side, a walk over the demangled tree on the
// other — and the two disagree for exactly the names that must still join:
// a C tag enum is `enum` to its descriptor but mangles (and demangles) as a
// `structure`, and a C typedef promoted to a nominal type demangles as a
// `typeAlias` (evolution proposal `type-import-info-identity`). Keying on
// `kind` split such a type's conformance descriptor from its associated-type
// record and witness symbols, so the interface printed the conformance
// block without its `typealias` witness and the witness as a bare block.
extension TypeName {
    public static func == (lhs: TypeName, rhs: TypeName) -> Bool {
        lhs.node.structurallyEquals(rhs.node)
    }

    public func hash(into hasher: inout Hasher) {
        node.structuralHash(into: &hasher)
    }
}
