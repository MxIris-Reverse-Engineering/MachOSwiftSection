/// Builds an `ABIEvolution` from N ≥ 2 ordered snapshots by computing a
/// key → per-version presence/payload matrix directly — not by joining N−1
/// pairwise diffs. The matrix makes cross-version stories ("removed in v2,
/// re-added in v4") natural products rather than join special-cases, while
/// every per-transition comparison uses exactly the two-sided differ's
/// semantics (identity match on `identityKey`, change detection on
/// `payloadKey`, first-wins key collisions), so for N == 2 the events are the
/// two-sided `ABIDiff` verbatim.
public struct ABIEvolutionBuilder: Sendable {
    public init() {}

    /// Track a module's ABI across ordered persisted baselines (oldest first).
    ///
    /// Label resolution per version: the explicit `labels` entry if provided,
    /// else the document's `provenance.label`, else a positional `"v<n>"`.
    public func evolution(of documents: [ABISnapshotDocument], labels: [String]? = nil) throws -> ABIEvolution {
        if let labels, labels.count != documents.count {
            throw ABIEvolutionError.labelCountMismatch(labelCount: labels.count, versionCount: documents.count)
        }
        let versions = documents.enumerated().map { index, document in
            ABIVersionDescriptor(
                label: labels?[index] ?? document.provenance?.label ?? "v\(index + 1)",
                provenance: document.provenance
            )
        }
        return try evolution(of: documents.map(\.snapshot), versions: versions)
    }

    /// Track a module's ABI across ordered snapshots (oldest first) under an
    /// explicit version axis.
    public func evolution(of snapshots: [ABISnapshot], versions: [ABIVersionDescriptor]) throws -> ABIEvolution {
        guard snapshots.count >= 2 else {
            throw ABIEvolutionError.fewerThanTwoVersions(versionCount: snapshots.count)
        }
        guard snapshots.count == versions.count else {
            throw ABIEvolutionError.labelCountMismatch(labelCount: versions.count, versionCount: snapshots.count)
        }
        return ABIEvolution(
            versions: versions,
            types: containerLineages(snapshots.map(\.types)),
            protocols: containerLineages(snapshots.map(\.protocols)),
            typeExtensions: containerLineages(snapshots.map(\.typeExtensions)),
            protocolExtensions: containerLineages(snapshots.map(\.protocolExtensions)),
            typeAliasExtensions: containerLineages(snapshots.map(\.typeAliasExtensions)),
            conformanceExtensions: containerLineages(snapshots.map(\.conformanceExtensions)),
            globalVariables: memberLineages(perVersionMembers: snapshots.map(\.globalVariables)),
            globalFunctions: memberLineages(perVersionMembers: snapshots.map(\.globalFunctions))
        )
    }

    // MARK: - Container axis

    /// One container bucket (types, protocols, or an extension bucket) across
    /// all versions: `perVersionContainers[i]` is that bucket in version `i`.
    private func containerLineages(_ perVersionContainers: [[ContainerSnapshot]]) -> [ContainerLineage] {
        let keyedPerVersion = perVersionContainers.map { keyedFirstWins($0, by: \.key) }
        let orderedKeys = unionOfKeys(keyedPerVersion)

        var lineages: [ContainerLineage] = []
        for containerKey in orderedKeys {
            let perVersion = keyedPerVersion.map { $0[containerKey] }
            let presence = perVersion.map { $0 != nil }
            let containerEvents = presenceTransitionEvents(presence)
            let members = memberLineages(perVersionMembers: perVersion.map { $0?.members })
            guard !containerEvents.isEmpty || !members.isEmpty else { continue }
            // Name/kind from the latest appearance, so a report shows the most
            // recent spelling of the container.
            let latest = perVersion.reversed().compactMap { $0 }.first!
            lineages.append(ContainerLineage(
                key: containerKey,
                name: latest.name,
                containerKind: latest.kind,
                presence: presence,
                events: containerEvents,
                memberLineages: members
            ))
        }
        return lineages.sorted { $0.key.sortKey < $1.key.sortKey }
    }

    // MARK: - Member axis

    /// Member lifelines across versions. `perVersionMembers[i] == nil` means
    /// the owning container is absent in version `i` (globals pass every
    /// version non-nil). Member events are computed only for transitions where
    /// both adjacent versions have the container — a container-level
    /// appearance/disappearance is the container's own event, and enumerating
    /// members across the gap would diverge from the two-sided differ (which
    /// leaves an added/removed container's `memberChanges` empty).
    private func memberLineages(perVersionMembers: [[MemberRecord]?]) -> [MemberLineage] {
        let keyedPerVersion = perVersionMembers.map { members in
            members.map { keyedFirstWins($0, by: \.identityKey) }
        }
        let orderedKeys = unionOfKeys(keyedPerVersion.map { $0 ?? [:] })

        var lineages: [MemberLineage] = []
        for memberKey in orderedKeys {
            let perVersion = keyedPerVersion.map { $0?[memberKey] }
            let presence = perVersion.map { $0 != nil }

            var events: [LineageEvent] = []
            for versionIndex in 1 ..< perVersion.count {
                guard keyedPerVersion[versionIndex - 1] != nil, keyedPerVersion[versionIndex] != nil else {
                    continue
                }
                let oldRecord = perVersion[versionIndex - 1]
                let newRecord = perVersion[versionIndex]
                switch (oldRecord, newRecord) {
                case (nil, let newRecord?):
                    events.append(LineageEvent(versionIndex: versionIndex, status: .added, newSignature: newRecord.signature))
                case (let oldRecord?, nil):
                    events.append(LineageEvent(versionIndex: versionIndex, status: .removed, oldSignature: oldRecord.signature))
                case (let oldRecord?, let newRecord?) where oldRecord.payloadKey != newRecord.payloadKey:
                    events.append(LineageEvent(
                        versionIndex: versionIndex,
                        status: .modified,
                        oldSignature: oldRecord.signature,
                        newSignature: newRecord.signature
                    ))
                default:
                    break
                }
            }
            guard !events.isEmpty else { continue }
            // The record must exist somewhere on the axis for an event to have
            // been produced, so the latest appearance always resolves a kind.
            let kind = perVersion.reversed().compactMap { $0 }.first!.kind
            lineages.append(MemberLineage(
                key: memberKey,
                kind: kind,
                presence: presence,
                events: events
            ))
        }
        return lineages.sorted { $0.key.sortKey < $1.key.sortKey }
    }

    // MARK: - Primitives

    /// `.added` / `.removed` events at every adjacent presence flip.
    private func presenceTransitionEvents(_ presence: [Bool]) -> [LineageEvent] {
        var events: [LineageEvent] = []
        for versionIndex in 1 ..< presence.count {
            switch (presence[versionIndex - 1], presence[versionIndex]) {
            case (false, true):
                events.append(LineageEvent(versionIndex: versionIndex, status: .added))
            case (true, false):
                events.append(LineageEvent(versionIndex: versionIndex, status: .removed))
            default:
                break
            }
        }
        return events
    }

    /// The union of every version's keys, in stable sorted order.
    private func unionOfKeys<Value>(_ keyedPerVersion: [[ABIKey: Value]]) -> [ABIKey] {
        var seen: Set<ABIKey> = []
        var union: [ABIKey] = []
        for keyed in keyedPerVersion {
            for key in keyed.keys where !seen.contains(key) {
                seen.insert(key)
                union.append(key)
            }
        }
        return union.sorted { $0.sortKey < $1.sortKey }
    }
}

/// Input-shape failures of `ABIEvolutionBuilder`.
public enum ABIEvolutionError: Error, Equatable, CustomStringConvertible {
    case fewerThanTwoVersions(versionCount: Int)
    case labelCountMismatch(labelCount: Int, versionCount: Int)

    public var description: String {
        switch self {
        case .fewerThanTwoVersions(let versionCount):
            return "ABI evolution needs at least 2 versions, got \(versionCount)."
        case .labelCountMismatch(let labelCount, let versionCount):
            return "Got \(labelCount) labels for \(versionCount) versions; the counts must match."
        }
    }
}
