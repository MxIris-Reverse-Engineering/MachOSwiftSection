public enum SymbolicReferenceKind: UInt8, CaseIterable, Sendable {
    /// A symbolic reference to a context descriptor, representing the
    /// (unapplied generic) context.
    case context
    /// A symbolic reference to an accessor function, which can be executed in
    /// the process to get a pointer to the referenced entity.
    case accessorFunctionReference
    /// A symbolic reference to a unique extended existential type shape.
    case uniqueExtendedExistentialTypeShape
    /// A symbolic reference to a non-unique extended existential type shape.
    case nonUniqueExtendedExistentialTypeShape
    /// A symbolic reference to a objective C protocol ref.
    case objectiveCProtocol
}

public enum SymbolicReference {
    public static func symbolicReference(for rawValue: UInt8) -> (SymbolicReferenceKind, Directness)? {
        switch rawValue {
        case 0x01:
            return (.context, .direct)
        case 0x02:
            return (.context, .indirect)
        case 0x09:
            return (.accessorFunctionReference, .direct)
        case 0x0A:
            return (.uniqueExtendedExistentialTypeShape, .indirect)
        case 0x0B:
            return (.nonUniqueExtendedExistentialTypeShape, .direct)
        case 0x0C:
            return (.objectiveCProtocol, .direct)
        default:
            return nil
        }
    }
}

public typealias SymbolicReferenceResolver = @Sendable (SymbolicReferenceKind, Directness, Int) -> Node?
