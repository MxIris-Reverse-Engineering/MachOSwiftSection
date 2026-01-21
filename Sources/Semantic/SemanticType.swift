public enum SemanticType: Hashable, Codable, Sendable {
    public enum TypeKind: CaseIterable, Hashable, Codable, Sendable {
        case `enum`
        case `struct`
        case `class`
        case `protocol`
        case other
    }

    public enum Context: CaseIterable, Hashable, Codable, Sendable {
        case declaration
        case name
    }

    case standard
    case comment
    case keyword
    case variable
    case numeric
    case argument
    case error
    case type(TypeKind, Context)
    case member(Context)
    case function(Context)
    case other
}
