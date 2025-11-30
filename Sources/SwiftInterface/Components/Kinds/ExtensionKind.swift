public enum ExtensionKind: Hashable, Codable, Sendable {
    case type(TypeKind)
    case `protocol`
    case typeAlias
}
