import MemberwiseInit
import Semantic
import Demangling

@MemberwiseInit(.public)
public struct ExtensionName: DefinitionName, Hashable, Sendable {
    public let node: NodeReference

    public let kind: ExtensionKind

    @SemanticStringBuilder
    public func print() -> SemanticString {
        switch kind {
        case .type(.enum):
            TypeDeclaration(kind: .enum, name)
        case .type(.struct):
            TypeDeclaration(kind: .struct, name)
        case .type(.class):
            TypeDeclaration(kind: .class, name)
        case .protocol:
            TypeDeclaration(kind: .protocol, name)
        case .typeAlias:
            TypeDeclaration(kind: .other, name)
        }
    }
}

extension ExtensionName {
    package var isProtocol: Bool {
        switch kind {
        case .protocol: return true
        default: return false
        }
    }
}

// MARK: - Structural Hashable

// See `TypeName`: names hash and compare by node STRUCTURE, not by
// `NodeReference`'s store-identity `Hashable`, and `kind` takes no part —
// the node already tells a protocol from a type from a typealias, while the
// `TypeKind` inside `.type` is producer-dependent for C-imported types.
extension ExtensionName {
    public static func == (lhs: ExtensionName, rhs: ExtensionName) -> Bool {
        lhs.node.structurallyEquals(rhs.node)
    }

    public func hash(into hasher: inout Hasher) {
        node.structuralHash(into: &hasher)
    }
}
