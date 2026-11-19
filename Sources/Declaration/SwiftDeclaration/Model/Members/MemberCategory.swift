import MachOSwiftSection

/// The symbol-backed member categories, in the canonical declaration order that
/// every `byCategory` rendering path walks — the printer's
/// `printMembersByCategory`, the diff renderer's per-container member diffing,
/// and `OrderedMember.allMembers(from:)`.
///
/// The order lives here and nowhere else: each consumer drives itself from
/// `allCases`, and any new category added here forces every exhaustive `switch`
/// over `MemberCategory` to handle it — so a category can never be silently
/// rendered by one path while dropped by another.
public enum MemberCategory: CaseIterable, Sendable {
    case allocators
    case variables
    case functions
    case subscripts
    case staticVariables
    case staticFunctions
    case staticSubscripts
}

extension Definition {
    /// This definition's members in `category`, wrapped as `OrderedMember`s in
    /// declaration order.
    ///
    /// Static and instance variants collapse onto the same `OrderedMember` case
    /// (a member's static-ness is intrinsic to its own model, not to the
    /// category), matching how every renderer treats the two identically.
    public func members(in category: MemberCategory) -> [OrderedMember] {
        switch category {
        case .allocators: allocators.map { .allocator($0) }
        case .variables: variables.map { .variable($0) }
        case .functions: functions.map { .function($0) }
        case .subscripts: subscripts.map { .subscript($0) }
        case .staticVariables: staticVariables.map { .variable($0) }
        case .staticFunctions: staticFunctions.map { .function($0) }
        case .staticSubscripts: staticSubscripts.map { .subscript($0) }
        }
    }
}
