import MemberwiseInit
import Demangle
import Semantic

@MemberwiseInit(.public)
public struct TypeName: Hashable, Sendable {
    public let name: String
    public let kind: TypeKind

    public var currentName: String {
        name.components(separatedBy: ".").last ?? name
    }

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
