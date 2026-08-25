import SwiftDiffing

/// Key-addressed view of an `ABIEvolution`'s lineages — the single source of
/// annotation facts for the evolution interface renderer.
///
/// The renderer never derives lifecycle events itself: it computes each
/// declaration's `ABIKey` (the same construction `ABIDiffer` freezes into
/// snapshots) and looks the lineage up here. A hit yields an
/// ``EvolutionAnnotation``; a miss means the declaration is present on every
/// version and never changed (`ABIEvolution` materializes changed lineages
/// only), which renders with no annotation. This is what keeps the annotated
/// interface, the lineage report, and the JSON permanently in agreement.
///
/// Container keys are merged across all six buckets into one map — type,
/// protocol, and extension-container keys are disjoint by construction (full
/// remangled identities vs. the namespaced `extbucket:` composition). Lookups
/// are first-wins on duplicate keys, matching `ABIDiffer.keyed`.
struct EvolutionAnnotationIndex: Sendable {
    private let containerLineagesByKey: [ABIKey: ContainerLineage]
    private let memberLineagesByContainerKey: [ABIKey: [ABIKey: MemberLineage]]
    private let globalLineagesByKey: [ABIKey: MemberLineage]

    init(evolution: ABIEvolution) {
        var containers: [ABIKey: ContainerLineage] = [:]
        var membersByContainer: [ABIKey: [ABIKey: MemberLineage]] = [:]
        for lineage in evolution.allContainerLineages where containers[lineage.key] == nil {
            containers[lineage.key] = lineage
            var members: [ABIKey: MemberLineage] = [:]
            members.reserveCapacity(lineage.memberLineages.count)
            for memberLineage in lineage.memberLineages where members[memberLineage.key] == nil {
                members[memberLineage.key] = memberLineage
            }
            membersByContainer[lineage.key] = members
        }
        var globals: [ABIKey: MemberLineage] = [:]
        for lineage in evolution.allGlobalLineages where globals[lineage.key] == nil {
            globals[lineage.key] = lineage
        }
        self.containerLineagesByKey = containers
        self.memberLineagesByContainerKey = membersByContainer
        self.globalLineagesByKey = globals
    }

    /// The annotation for a container header, or `nil` when the container has
    /// no presence events of its own. A container that exists on every version
    /// but has member events still returns `nil` here — the signal belongs on
    /// the member lines, not the header (container lineages store only
    /// `.added`/`.removed`; "modified" is derivable and deliberately unstored).
    func containerAnnotation(forKey key: ABIKey) -> EvolutionAnnotation? {
        guard let lineage = containerLineagesByKey[key], !lineage.events.isEmpty else { return nil }
        return EvolutionAnnotation(presence: lineage.presence, events: lineage.events)
    }

    func memberAnnotation(forContainerKey containerKey: ABIKey, memberKey: ABIKey) -> EvolutionAnnotation? {
        guard let lineage = memberLineagesByContainerKey[containerKey]?[memberKey] else { return nil }
        return EvolutionAnnotation(presence: lineage.presence, events: lineage.events)
    }

    func globalAnnotation(forKey key: ABIKey) -> EvolutionAnnotation? {
        guard let lineage = globalLineagesByKey[key] else { return nil }
        return EvolutionAnnotation(presence: lineage.presence, events: lineage.events)
    }
}
