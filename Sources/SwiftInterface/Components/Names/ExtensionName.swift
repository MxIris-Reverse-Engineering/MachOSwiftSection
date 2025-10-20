import MemberwiseInit
import Semantic
import Demangling

@MemberwiseInit(.public)
public struct ExtensionName: DefinitionName, Hashable, Sendable {
    public let node: Node
    
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
