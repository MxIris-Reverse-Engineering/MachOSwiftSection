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
extension TypeName {
    public static func == (lhs: TypeName, rhs: TypeName) -> Bool {
        lhs.kind == rhs.kind && lhs.node.structurallyEquals(rhs.node)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        node.structuralHash(into: &hasher)
    }
}
