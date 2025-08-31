import MemberwiseInit
import Demangle
import Semantic

@MemberwiseInit
struct TypeName: Hashable, Sendable {
    let name: String
    let kind: TypeKind

    var currentName: String {
        name.components(separatedBy: ".").last ?? name
    }

    @SemanticStringBuilder
    func print() -> SemanticString {
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
