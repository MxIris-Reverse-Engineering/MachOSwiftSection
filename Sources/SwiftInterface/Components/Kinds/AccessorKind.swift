public enum AccessorKind: String, Codable, Sendable {
    case getter
    case setter
    case modifyAccessor
    case readAccessor
    case none
}
