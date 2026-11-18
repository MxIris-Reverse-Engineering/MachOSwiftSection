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
    /// SE-0400: an `init` accessor, which initializes the stored properties
    /// its `@storageRestrictions(initializes:)` lists when an initializer
    /// assigns the property (symbol suffix `vi`). Only the type's own
    /// initializers call it, so it is never in a vtable or a witness table,
    /// and the compiler gives it `internal` access unless it is declared
    /// `@usableFromInline`: an optimized, dead-stripped image keeps only the
    /// exported ones. The binary records nothing of the attribute (evolution
    /// proposal `init-accessor-recovery`).
    case initAccessor
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
        case .initAccessor: "init"
        case .none: nil
        }
    }
}
