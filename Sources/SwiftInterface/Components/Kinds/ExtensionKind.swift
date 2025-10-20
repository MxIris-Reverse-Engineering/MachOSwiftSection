public enum ExtensionKind: Hashable, Sendable {
    case type(TypeKind)
    case `protocol`
    case typeAlias
}
