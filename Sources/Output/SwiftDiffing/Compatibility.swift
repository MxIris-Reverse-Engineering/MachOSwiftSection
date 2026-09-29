/// A change's backward-compatibility verdict.
///
/// Heuristic: a new declaration is `.additive` (callers built against the old
/// ABI keep working), anything removed or re-signed is `.breaking`; a modified
/// container is breaking iff any of its member changes is breaking. One
/// record-level refinement layers on top (`compatibilityOverride`, computed by
/// `MemberRecord.compatibilityOverride(old:new:)`): a protocol requirement
/// added **without** a default implementation is breaking (existing
/// conformances lack the witness — Swift library evolution permits requirement
/// additions only with a default), and a stripped slot whose only change is
/// gaining its default implementation is additive.
///
/// Known limitation — `@frozen` is not recoverable from the binary, so the
/// verdict treats *every* type as resilient. Whether appending a stored field
/// is additive (resilient struct) or breaking (`@frozen` struct) hinges on the
/// source `@frozen` attribute, which the compiler consumes at layout time and
/// does **not** emit: `TypeContextDescriptorFlags` carries no frozen bit, and
/// neither the field descriptors nor the reflection records record one (verified
/// against `swift/include/swift/ABI/MetadataValues.h`). The only proxy,
/// `hasSingletonMetadataInitialization`, means "needs runtime layout
/// completion", which diverges from `@frozen` in real cases (a `@frozen` type
/// with a resilient stored field still needs singleton init; a module built
/// without library evolution makes every type fixed-layout with no `@frozen` in
/// sight). Baking that proxy into the verdict would be confidently wrong, so a
/// field *addition* is reported `.additive` unconditionally and the reader must
/// apply frozen knowledge themselves.
/// See `Documentations/Internal/ABIDiffDesignAndLimitations.md`.
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
    /// Whether this member-level change keeps the old ABI working: the
    /// record-level refinement when present, else the status rule.
    public var compatibility: Compatibility { compatibilityOverride ?? status.compatibility }
}

extension LineageEvent {
    /// Whether this transition keeps the old ABI working: the record-level
    /// refinement when present, else the status rule.
    public var compatibility: Compatibility { compatibilityOverride ?? status.compatibility }
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
    ///
    /// Assumes resilient (non-`@frozen`) types: frozen-ness is not recoverable
    /// from the binary (see ``Compatibility``), so a stored-field addition to a
    /// `@frozen` type is *not* flagged here.
    public var isBackwardCompatible: Bool {
        !hasBreakingChange
    }
}

extension ABIEvolution {
    /// The verdict for each adjacent transition on the axis (`versions.count -
    /// 1` entries; entry `i` covers `versions[i] → versions[i+1]`). A
    /// transition is breaking iff any lineage carries a removed/modified event
    /// there. The same `@frozen` caveat as ``Compatibility`` applies.
    public var transitionCompatibilities: [Compatibility] {
        var breakingTransitions = Set<Int>()
        for lineage in allContainerLineages {
            for event in lineage.events where event.compatibility == .breaking {
                breakingTransitions.insert(event.versionIndex)
            }
            for memberLineage in lineage.memberLineages {
                for event in memberLineage.events where event.compatibility == .breaking {
                    breakingTransitions.insert(event.versionIndex)
                }
            }
        }
        for lineage in allGlobalLineages {
            for event in lineage.events where event.compatibility == .breaking {
                breakingTransitions.insert(event.versionIndex)
            }
        }
        return (1 ..< versions.count).map {
            breakingTransitions.contains($0) ? .breaking : .additive
        }
    }

    /// `true` when at least one transition on the axis is ABI-breaking.
    public var hasBreakingChange: Bool {
        transitionCompatibilities.contains(.breaking)
    }

    /// The `versionIndex` of the earliest breaking transition (the version the
    /// break landed in), or `nil` when the whole axis is additive.
    public var firstBreakingVersionIndex: Int? {
        transitionCompatibilities.firstIndex(of: .breaking).map { $0 + 1 }
    }
}
