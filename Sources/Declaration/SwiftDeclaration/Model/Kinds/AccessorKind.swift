public enum AccessorKind: Sendable, Codable {
    case getter
    case setter
    case modifyAccessor
    case readAccessor
    /// SE-0507: a `borrow` accessor, which returns a borrow of the stored
    /// value instead of a copy (symbol suffix `vb`).
    case borrowAccessor
    /// SE-0507: a `mutate` accessor, which returns an `inout` projection of
    /// the stored value (symbol suffix `vz`).
    case mutateAccessor
    case none

    /// Label used in address comments. Returns `nil` for stored properties (`.none`).
    public var addressLabel: String? {
        switch self {
        case .getter: "getter"
        case .setter: "setter"
        case .modifyAccessor: "modify"
        case .readAccessor: "read"
        case .borrowAccessor: "borrow"
        case .mutateAccessor: "mutate"
        case .none: nil
        }
    }
}
