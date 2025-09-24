import MemberwiseInit
import Semantic

@MemberwiseInit(.public)
public struct TypeName: DefinitionName, Hashable, Sendable {
    public let name: String
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
        ExtensionName(name: name, kind: .type(kind))
    }
}
