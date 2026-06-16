/// A change's backward-compatibility verdict.
///
/// Heuristic for now: a new declaration is `.additive` (callers built against
/// the old ABI keep working), anything removed or re-signed is `.breaking`.
/// TODO(P2): resilience-aware refinement — e.g. appending a member to a
/// non-frozen struct / resilient class is additive, whereas the same change to
/// a frozen/`@frozen` type is breaking; this heuristic conservatively calls a
/// modified container breaking if any member change is breaking.
public enum Compatibility: Sendable, Codable, Equatable {
    case additive
    case breaking
}

extension ChangeStatus {
    var compatibility: Compatibility {
        switch self {
        case .added: return .additive
        case .removed, .modified: return .breaking
        }
    }
}

extension MemberChange {
    /// Whether this member-level change keeps the old ABI working.
    public var compatibility: Compatibility { status.compatibility }
}

extension ContainerChange {
    /// Whether this container-level change keeps the old ABI working. A removed
    /// container is breaking; an added one is additive; a modified one is
    /// breaking iff any of its member changes is breaking.
    public var compatibility: Compatibility {
        switch status {
        case .added: return .additive
        case .removed: return .breaking
        case .modified: return memberChanges.contains { $0.compatibility == .breaking } ? .breaking : .additive
        }
    }
}

extension ABIDiff {
    private var allContainerChanges: [ContainerChange] {
        types + protocols + typeExtensions + protocolExtensions + typeAliasExtensions + conformanceExtensions
    }

    /// Every container change classified as breaking.
    public var breakingContainerChanges: [ContainerChange] {
        allContainerChanges.filter { $0.compatibility == .breaking }
    }

    /// Every global member change classified as breaking.
    public var breakingGlobalChanges: [MemberChange] {
        (globalVariables + globalFunctions).filter { $0.compatibility == .breaking }
    }

    /// `true` when at least one change is ABI-breaking.
    public var hasBreakingChange: Bool {
        !breakingContainerChanges.isEmpty || !breakingGlobalChanges.isEmpty
    }

    /// `true` when the diff is non-empty but every change is additive — old
    /// callers keep working. An empty diff is trivially backward-compatible.
    public var isBackwardCompatible: Bool {
        !hasBreakingChange
    }
}
