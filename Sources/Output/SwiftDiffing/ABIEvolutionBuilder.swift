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
        try Self.validate(versionCount: snapshots.count, descriptorCount: versions.count)
        return evolution(
            of: snapshots,
            versions: versions,
            keyCollisionsByVersion: snapshots.map { $0.keyCollisions() },
            imageGroups: nil
        )
    }

    /// Track a module's ABI across ordered versions (oldest first), each
    /// made up of a group of images (evolution proposal
    /// `image-group-evolution`) — a module Apple split across images, such
    /// as SwiftUI and SwiftUICore.
    ///
    /// A version's images merge into one API surface (see
    /// `MergedImageGroup`), so a declaration that moved between them stays
    /// present instead of reading as removed and added; its lineage records
    /// the move in `imageMoves`, and every descriptor names its images in
    /// `imageNames`. An empty group is a version holding nothing.
    public func evolution(ofImageGroups imageGroups: [[ABIImageSnapshot]], versions: [ABIVersionDescriptor]) throws -> ABIEvolution {
        try Self.validate(versionCount: imageGroups.count, descriptorCount: versions.count)
        let mergedGroups = imageGroups.map(MergedImageGroup.init)
        return evolution(
            of: mergedGroups.map(\.snapshot),
            versions: zip(versions, mergedGroups).map { version, mergedGroup in
                ABIVersionDescriptor(label: version.label, provenance: version.provenance, imageNames: mergedGroup.imageNames)
            },
            keyCollisionsByVersion: mergedGroups.map(\.keyCollisions),
            imageGroups: mergedGroups
        )
    }

    private static func validate(versionCount: Int, descriptorCount: Int) throws {
        guard versionCount >= 2 else {
            throw ABIEvolutionError.fewerThanTwoVersions(versionCount: versionCount)
        }
        guard versionCount == descriptorCount else {
            throw ABIEvolutionError.labelCountMismatch(labelCount: descriptorCount, versionCount: versionCount)
        }
    }

    /// The matrix over validated input. `imageGroups`, one per version, says
    /// which images hold what when the versions are groups of images.
    private func evolution(
        of snapshots: [ABISnapshot],
        versions: [ABIVersionDescriptor],
        keyCollisionsByVersion: [[ABIKeyCollision]],
        imageGroups: [MergedImageGroup]?
    ) -> ABIEvolution {
        let remangleFallbacksByVersion = snapshots.map { $0.remangleFallbacks() }
        let hidesNonExportedMembers = snapshots.map { !$0.hasLocalSwiftSymbols }
        let versionIndicesWithoutLocalSwiftSymbols = hidesNonExportedMembers.indices.filter { hidesNonExportedMembers[$0] }
        // Globals have no container: every version can hold them.
        let everyVersionPresent = [PresenceObservation](repeating: .present, count: snapshots.count)
        return ABIEvolution(
            versions: versions,
            types: containerLineages(snapshots.map(\.types), hidesNonExportedMembers, imageGroups?.map(\.types)),
            protocols: containerLineages(snapshots.map(\.protocols), hidesNonExportedMembers, imageGroups?.map(\.protocols)),
            typeExtensions: containerLineages(snapshots.map(\.typeExtensions), hidesNonExportedMembers, imageGroups?.map(\.typeExtensions)),
            protocolExtensions: containerLineages(snapshots.map(\.protocolExtensions), hidesNonExportedMembers, imageGroups?.map(\.protocolExtensions)),
            typeAliasExtensions: containerLineages(snapshots.map(\.typeAliasExtensions), hidesNonExportedMembers, imageGroups?.map(\.typeAliasExtensions)),
            conformanceExtensions: containerLineages(snapshots.map(\.conformanceExtensions), hidesNonExportedMembers, imageGroups?.map(\.conformanceExtensions)),
            globalVariables: memberLineages(
                perVersionMembers: snapshots.map(\.globalVariables),
                containerObservations: everyVersionPresent,
                hidesNonExportedMembers,
                perVersionImageNames: imageGroups?.map(\.globalVariableImageNames),
                containerImageNames: nil
            ),
            globalFunctions: memberLineages(
                perVersionMembers: snapshots.map(\.globalFunctions),
                containerObservations: everyVersionPresent,
                hidesNonExportedMembers,
                perVersionImageNames: imageGroups?.map(\.globalFunctionImageNames),
                containerImageNames: nil
            ),
            keyCollisionsByVersion: keyCollisionsByVersion.allSatisfy(\.isEmpty) ? nil : keyCollisionsByVersion,
            remangleFallbacksByVersion: remangleFallbacksByVersion.allSatisfy(\.isEmpty) ? nil : remangleFallbacksByVersion,
            versionIndicesWithoutLocalSwiftSymbols: versionIndicesWithoutLocalSwiftSymbols.isEmpty ? nil : versionIndicesWithoutLocalSwiftSymbols
        )
    }

    // MARK: - Container axis

    /// One container bucket (types, protocols, or an extension bucket) across
    /// all versions: `perVersionContainers[i]` is that bucket in version `i`.
    /// `hidesNonExportedMembers[i]` says version `i`'s image carries no local
    /// Swift symbols (see `UnobservablePresence.swift`). `perVersionImages`,
    /// when the versions are groups of images, says which images hold the
    /// bucket's containers and members in each version.
    private func containerLineages(
        _ perVersionContainers: [[ContainerSnapshot]],
        _ hidesNonExportedMembers: [Bool],
        _ perVersionImages: [BucketImageAttribution]?
    ) -> [ContainerLineage] {
        let keyedPerVersion = perVersionContainers.map { keyedFirstWins($0, by: \.key) }
        let orderedKeys = unionOfKeys(keyedPerVersion)

        var lineages: [ContainerLineage] = []
        for containerKey in orderedKeys {
            let perVersion = keyedPerVersion.map { $0[containerKey] }
            let observations = PresenceObservation.observations(
                of: perVersion,
                hidesNonExportedMembers: hidesNonExportedMembers,
                needsLocalSymbolsToBeSeen: \.needsLocalSymbolsToBeSeen
            )
            let resolution = PresenceResolution(observations)
            let containerEvents = resolution.presenceEvents()
            let containerImageNames = perVersionImages?.map { $0.containerImageNames[containerKey] }
            let members = memberLineages(
                perVersionMembers: perVersion.map { $0?.members },
                containerObservations: observations,
                hidesNonExportedMembers,
                perVersionImageNames: perVersionImages?.map { $0.memberImageNames[containerKey] ?? [:] },
                containerImageNames: containerImageNames
            )
            let presenceStates = resolution.presenceStatesIfAnyUnobserved
            let imageMoves = containerImageNames.map { ImageMove.moves(observations: observations, imageNames: $0) } ?? []
            guard !containerEvents.isEmpty || !members.isEmpty || presenceStates != nil || !imageMoves.isEmpty else { continue }
            // Name/kind from the latest appearance, so a report shows the most
            // recent spelling of the container.
            let latest = perVersion.reversed().compactMap { $0 }.first!
            lineages.append(ContainerLineage(
                key: containerKey,
                name: latest.name,
                containerKind: latest.kind,
                presence: resolution.presence,
                events: containerEvents,
                memberLineages: members,
                presenceStates: presenceStates,
                imageMoves: imageMoves.isEmpty ? nil : imageMoves
            ))
        }
        return lineages.sorted { $0.key.sortKey < $1.key.sortKey }
    }

    // MARK: - Member axis

    /// Member lifelines across versions. `perVersionMembers[i] == nil` means
    /// the owning container is absent from version `i` or hidden there, as
    /// `containerObservations[i]` tells (globals pass every version present).
    /// Member events are computed only for transitions where the container
    /// is observed present on both sides — a container-level
    /// appearance/disappearance is the container's own event, and enumerating
    /// members across the gap would diverge from the two-sided differ (which
    /// leaves an added/removed container's `memberChanges` empty). A member
    /// cannot be seen where its container cannot.
    ///
    /// When the versions are groups of images, `perVersionImageNames[i]`
    /// maps each member identity to the images holding it in version `i`,
    /// and `containerImageNames[i]` names the container's images there (`nil`
    /// for the globals, which have no container): a member that moved along
    /// with its container is the container's move.
    private func memberLineages(
        perVersionMembers: [[MemberRecord]?],
        containerObservations: [PresenceObservation],
        _ hidesNonExportedMembers: [Bool],
        perVersionImageNames: [[ABIKey: [String]]]? = nil,
        containerImageNames: [[String]?]? = nil
    ) -> [MemberLineage] {
        let keyedPerVersion = perVersionMembers.map { members in
            members.map { keyedFirstWins($0, by: \.identityKey) }
        }
        let orderedKeys = unionOfKeys(keyedPerVersion.map { $0 ?? [:] })
        let versionCount = perVersionMembers.count

        var lineages: [MemberLineage] = []
        for memberKey in orderedKeys {
            let perVersion = keyedPerVersion.map { $0?[memberKey] }
            let memberObservations = PresenceObservation.observations(
                of: perVersion,
                hidesNonExportedMembers: hidesNonExportedMembers,
                needsLocalSymbolsToBeSeen: \.needsLocalSymbolsToBeSeen
            )
            let observations = (0 ..< versionCount).map { versionIndex -> PresenceObservation in
                switch containerObservations[versionIndex] {
                case .present: memberObservations[versionIndex]
                case .absent: .absent
                case .hidden: .hidden
                }
            }
            let resolution = PresenceResolution(observations)

            var events: [LineageEvent] = []
            for versionIndex in 1 ..< versionCount {
                guard containerObservations[versionIndex - 1] == .present, containerObservations[versionIndex] == .present,
                      observations[versionIndex - 1] != .hidden, observations[versionIndex] != .hidden
                else { continue }
                if let event = Self.memberEvent(old: perVersion[versionIndex - 1], new: perVersion[versionIndex], at: versionIndex, earliestVersionIndex: nil) {
                    events.append(event)
                }
            }
            for hiddenSpan in resolution.boundedHiddenSpans {
                let observedIndexBefore = hiddenSpan.lowerBound - 1
                let observedIndexAfter = hiddenSpan.upperBound + 1
                guard containerObservations[observedIndexBefore] == .present, containerObservations[observedIndexAfter] == .present else { continue }
                if let event = Self.memberEvent(
                    old: perVersion[observedIndexBefore],
                    new: perVersion[observedIndexAfter],
                    at: observedIndexAfter,
                    earliestVersionIndex: hiddenSpan.lowerBound
                ) {
                    events.append(event)
                }
            }
            events.sort { $0.versionIndex < $1.versionIndex }

            // Kept for its unobservable versions only where the member itself
            // went unseen and that says something: present on both sides, or
            // a bound left unknown. Where its container is unseen too, the
            // container's lineage tells that story, as an added or removed
            // container's does for its members; between two absences there
            // is nothing to tell.
            let hasTellingSpanOfItsOwn = resolution.states.unobservedSpans.contains { span in
                (span.state == .inferredPresent || !span.leavesTheBoundsKnown)
                    && span.versionIndices.contains { containerObservations[$0] == .present }
            }
            let imageMoves = perVersionImageNames.map { perVersionImageNames in
                ImageMove.moves(
                    observations: observations,
                    imageNames: perVersionImageNames.map { $0[memberKey] },
                    containerImageNames: containerImageNames
                )
            } ?? []
            guard !events.isEmpty || hasTellingSpanOfItsOwn || !imageMoves.isEmpty else { continue }
            let presenceStates = resolution.presenceStatesIfAnyUnobserved
            // The record exists somewhere on the axis for the key to be in the
            // union, so the latest appearance always resolves a kind.
            let latestRecord = perVersion.reversed().compactMap { $0 }.first!
            lineages.append(MemberLineage(
                key: memberKey,
                kind: latestRecord.kind,
                presence: resolution.presence,
                events: events,
                presenceStates: presenceStates,
                latestSignature: events.isEmpty ? latestRecord.signature : nil,
                imageMoves: imageMoves.isEmpty ? nil : imageMoves
            ))
        }
        return lineages.sorted { $0.key.sortKey < $1.key.sortKey }
    }

    // MARK: - Primitives

    /// The member-level change between two observed records, if any: added,
    /// removed, or modified on a payload change. `earliestVersionIndex` marks
    /// a change placed only between two observations around a hidden span.
    private static func memberEvent(old oldRecord: MemberRecord?, new newRecord: MemberRecord?, at versionIndex: Int, earliestVersionIndex: Int?) -> LineageEvent? {
        switch (oldRecord, newRecord) {
        case (nil, let newRecord?):
            return LineageEvent(
                versionIndex: versionIndex,
                status: .added,
                newSignature: newRecord.signature,
                compatibilityOverride: MemberRecord.compatibilityOverride(old: nil, new: newRecord),
                earliestVersionIndex: earliestVersionIndex
            )
        case (let oldRecord?, nil):
            return LineageEvent(
                versionIndex: versionIndex,
                status: .removed,
                oldSignature: oldRecord.signature,
                compatibilityOverride: MemberRecord.compatibilityOverride(old: oldRecord, new: nil),
                earliestVersionIndex: earliestVersionIndex
            )
        case (let oldRecord?, let newRecord?) where oldRecord.payloadKey != newRecord.payloadKey:
            return LineageEvent(
                versionIndex: versionIndex,
                status: .modified,
                oldSignature: oldRecord.signature,
                newSignature: newRecord.signature,
                compatibilityOverride: MemberRecord.compatibilityOverride(old: oldRecord, new: newRecord),
                earliestVersionIndex: earliestVersionIndex
            )
        default:
            return nil
        }
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
