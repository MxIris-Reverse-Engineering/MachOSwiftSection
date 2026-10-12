import MemberwiseInit
import Semantic
import Demangling

@MemberwiseInit(.public)
public struct ExtensionName: DefinitionName, Hashable, Sendable {
    public let node: NodeReference

    public let kind: ExtensionKind

    /// The extended type's name as an extension header spells it — with
    /// SE-0491 module selectors (`Swift::Duration`) when `usesModuleSelectors`
    /// is set. `name` itself stays dotted: it is also a lookup key.
    @SemanticStringBuilder
    public func print(usesModuleSelectors: Bool = false) -> SemanticString {
        let printedName = usesModuleSelectors ? name(using: DemangleOptions.interfaceTypeBuilderOnly.union(.useModuleSelectors)) : name
        switch kind {
        case .type(.enum):
            TypeDeclaration(kind: .enum, printedName)
        case .type(.struct):
            TypeDeclaration(kind: .struct, printedName)
        case .type(.class):
            TypeDeclaration(kind: .class, printedName)
        case .protocol:
            TypeDeclaration(kind: .protocol, printedName)
        case .typeAlias:
            TypeDeclaration(kind: .other, printedName)
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
