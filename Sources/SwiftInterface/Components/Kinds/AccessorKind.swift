public enum AccessorKind: Sendable {
    case getter
    case setter
    case modifyAccessor
    case readAccessor
    case none

    /// Label used in address comments. Returns `nil` for stored properties (`.none`).
    public var addressLabel: String? {
        switch self {
        case .getter: "getter"
        case .setter: "setter"
        case .modifyAccessor: "modify"
        case .readAccessor: "read"
        case .none: nil
        }
    }
}
