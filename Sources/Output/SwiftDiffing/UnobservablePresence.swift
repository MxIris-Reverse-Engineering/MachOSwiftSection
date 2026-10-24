/// What a version whose image carries no local Swift symbols cannot show, and
/// how the versions around such a span decide what is inferred inside it
/// (evolution proposal `evolution-unobservable-presence`). The evolution
/// builder and the two-sided differ share these rules, so for two versions
/// the two cannot disagree.
///
/// Such an image keeps only its exported Swift names — SwiftUI in the macOS
/// 13.0–14.8 dyld shared caches is the motivating case — so a member that
/// only a non-exported symbol evidences has no name there, whether or not it
/// exists. What its metadata records (types, protocols, conformances, stored
/// fields, enum cases, associated types and witnesses, stripped requirement
/// slots) and what it exports stays visible, and their absence stays an
/// observation.

extension MemberRecord {
    /// Whether an image without local Swift symbols could not show this
    /// member: only a symbol evidences it, and no verdict says that symbol
    /// is exported.
    var needsLocalSymbolsToBeSeen: Bool {
        isSymbolBacked && isExported != true
    }
}

extension ContainerSnapshot {
    /// Whether an image without local Swift symbols could not show this
    /// container: an extension that is not a conformance — no conformance
    /// record keeps it — made up only of members such an image cannot show.
    var needsLocalSymbolsToBeSeen: Bool {
        switch kind {
        case .typeExtension, .protocolExtension, .typeAliasExtension:
            return !members.isEmpty && members.allSatisfy(\.needsLocalSymbolsToBeSeen)
        case .type, .protocol, .conformanceExtension:
            return false
        }
    }
}

/// One version's observation of an identity, before inference.
enum PresenceObservation: Equatable {
    case present
    case absent
    /// Absent from a version that could not show it.
    case hidden
}

extension PresenceObservation {
    /// Per-version observations of one identity, `perVersion[index]` being
    /// its record in that version, if any.
    ///
    /// An absence is hidden when the version carries no local Swift symbols
    /// and the record of a nearest version that has the identity — on either
    /// side — needs local symbols to be seen: that is the shape the version
    /// would show, had it the declaration. Only when every such neighbour is
    /// visible without local symbols is the absence an observation. A
    /// one-sided `hidden` claims nothing false; a wrong `absent` would.
    static func observations<Record>(
        of perVersion: [Record?],
        hidesNonExportedMembers: [Bool],
        needsLocalSymbolsToBeSeen: (Record) -> Bool
    ) -> [PresenceObservation] {
        let versionCount = perVersion.count
        var nearestIndexBefore = [Int?](repeating: nil, count: versionCount)
        var lastPresentIndex: Int? = nil
        for versionIndex in 0 ..< versionCount {
            nearestIndexBefore[versionIndex] = lastPresentIndex
            if perVersion[versionIndex] != nil {
                lastPresentIndex = versionIndex
            }
        }
        var nearestIndexAfter = [Int?](repeating: nil, count: versionCount)
        var nextPresentIndex: Int? = nil
        for versionIndex in (0 ..< versionCount).reversed() {
            nearestIndexAfter[versionIndex] = nextPresentIndex
            if perVersion[versionIndex] != nil {
                nextPresentIndex = versionIndex
            }
        }
        return (0 ..< versionCount).map { versionIndex in
            if perVersion[versionIndex] != nil {
                return .present
            }
            guard hidesNonExportedMembers[versionIndex] else { return .absent }
            let neighbourIndices = [nearestIndexBefore[versionIndex], nearestIndexAfter[versionIndex]].compactMap { $0 }
            let isHidden = neighbourIndices.contains { neighbourIndex in
                perVersion[neighbourIndex].map(needsLocalSymbolsToBeSeen) ?? false
            }
            return isHidden ? .hidden : .absent
        }
    }
}

/// A lineage's per-version states once its hidden spans are inferred.
///
/// A maximal span of hidden versions with an observation on both sides takes
/// the state the two share: two presences make it inferred present (a gap
/// that real removals and re-additions leave in under 0.6% of the
/// declarations seen at both ends of a symbol-rich span, measured on the
/// SwiftUI axis), two absences leave it unobservable with nothing claimed.
/// Two different observations mean the change happened somewhere inside: an
/// event spanning it, first observed after it. A span reaching an end of the
/// axis has one side only and stays unobservable.
struct PresenceResolution {
    let states: [LineagePresenceState]

    /// Every maximal hidden span with an observation on both sides.
    let boundedHiddenSpans: [ClosedRange<Int>]

    init(_ observations: [PresenceObservation]) {
        var states: [LineagePresenceState] = observations.map { observation in
            switch observation {
            case .present: .present
            case .absent: .absent
            case .hidden: .unobservable
            }
        }
        var boundedHiddenSpans: [ClosedRange<Int>] = []
        var versionIndex = 0
        while versionIndex < observations.count {
            guard observations[versionIndex] == .hidden else {
                versionIndex += 1
                continue
            }
            let firstHiddenIndex = versionIndex
            while versionIndex < observations.count, observations[versionIndex] == .hidden {
                versionIndex += 1
            }
            let lastHiddenIndex = versionIndex - 1
            guard firstHiddenIndex > 0, versionIndex < observations.count else { continue }
            boundedHiddenSpans.append(firstHiddenIndex ... lastHiddenIndex)
            if observations[firstHiddenIndex - 1] == .present, observations[versionIndex] == .present {
                for hiddenIndex in firstHiddenIndex ... lastHiddenIndex {
                    states[hiddenIndex] = .inferredPresent
                }
            }
        }
        self.states = states
        self.boundedHiddenSpans = boundedHiddenSpans
    }

    /// Present, observed or inferred, per version.
    var presence: [Bool] {
        states.map { $0 == .present || $0 == .inferredPresent }
    }

    /// The states, when some version was not observed; `nil` otherwise.
    var presenceStatesIfAnyUnobserved: [LineagePresenceState]? {
        states.allSatisfy(\.isObserved) ? nil : states
    }

    /// `.added` / `.removed` at every flip between adjacent observations,
    /// and one event across every bounded hidden span whose sides differ.
    func presenceEvents() -> [LineageEvent] {
        var events: [LineageEvent] = []
        for versionIndex in 1 ..< max(states.count, 1) {
            switch (states[versionIndex - 1], states[versionIndex]) {
            case (.absent, .present):
                events.append(LineageEvent(versionIndex: versionIndex, status: .added))
            case (.present, .absent):
                events.append(LineageEvent(versionIndex: versionIndex, status: .removed))
            default:
                break
            }
        }
        for hiddenSpan in boundedHiddenSpans {
            let observedIndexAfter = hiddenSpan.upperBound + 1
            switch (states[hiddenSpan.lowerBound - 1], states[observedIndexAfter]) {
            case (.absent, .present):
                events.append(LineageEvent(versionIndex: observedIndexAfter, status: .added, earliestVersionIndex: hiddenSpan.lowerBound))
            case (.present, .absent):
                events.append(LineageEvent(versionIndex: observedIndexAfter, status: .removed, earliestVersionIndex: hiddenSpan.lowerBound))
            default:
                break
            }
        }
        return events.sorted { $0.versionIndex < $1.versionIndex }
    }
}

/// A maximal run of versions in which a lineage was not observed, all in one
/// state: ``LineagePresenceState/inferredPresent`` or
/// ``LineagePresenceState/unobservable``.
public struct UnobservedSpan: Sendable, Equatable {
    public let versionIndices: ClosedRange<Int>
    public let state: LineagePresenceState

    public init(versionIndices: ClosedRange<Int>, state: LineagePresenceState) {
        self.versionIndices = versionIndices
        self.state = state
    }
}

extension Array where Element == LineagePresenceState {
    /// Every maximal run of one unobserved state, in axis order — what the
    /// reports phrase as `inferred present in 13.0–14.8` or `not observable
    /// in 13.0`.
    public var unobservedSpans: [UnobservedSpan] {
        var spans: [UnobservedSpan] = []
        var versionIndex = 0
        while versionIndex < count {
            let state = self[versionIndex]
            guard !state.isObserved else {
                versionIndex += 1
                continue
            }
            let firstIndex = versionIndex
            while versionIndex < count, self[versionIndex] == state {
                versionIndex += 1
            }
            spans.append(UnobservedSpan(versionIndices: firstIndex ... versionIndex - 1, state: state))
        }
        return spans
    }
}

extension Array where Element == ABIVersionDescriptor {
    /// The labels of a run of versions: `13.0` for one, `13.0–14.8` for
    /// several.
    public func labels(spanning versionIndices: ClosedRange<Int>) -> String {
        let firstLabel = self[versionIndices.lowerBound].label
        guard versionIndices.count > 1 else { return firstLabel }
        return firstLabel + "–" + self[versionIndices.upperBound].label
    }

    /// The labels of a set of versions, contiguous runs collapsed:
    /// `11.0, 13.0–14.8`.
    public func labels(ofVersionsAt versionIndices: [Int]) -> String {
        var runs: [ClosedRange<Int>] = []
        for versionIndex in versionIndices.sorted() {
            if let lastRun = runs.last, lastRun.upperBound + 1 == versionIndex {
                runs[runs.count - 1] = lastRun.lowerBound ... versionIndex
            } else {
                runs.append(versionIndex ... versionIndex)
            }
        }
        return runs.map { labels(spanning: $0) }.joined(separator: ", ")
    }
}

extension LineageEvent {
    /// Where the event is placed, phrased against the axis: `in 3.0` when
    /// exact, `between 1.0 and 3.0` — the last version seen before it and
    /// the first seen after — when it spans versions that could not show it.
    public func placement(on versions: [ABIVersionDescriptor]) -> String {
        guard let earliestVersionIndex, earliestVersionIndex > 0, versions.indices.contains(versionIndex) else {
            let label = versions.indices.contains(versionIndex) ? versions[versionIndex].label : "v\(versionIndex + 1)"
            return "in " + label
        }
        return "between \(versions[earliestVersionIndex - 1].label) and \(versions[versionIndex].label)"
    }
}

/// A declaration one side of a two-sided diff cannot show (evolution
/// proposal `evolution-unobservable-presence`): the other side has it, only
/// a non-exported symbol evidences it there, and this side's image carries
/// no local Swift symbols. Neither added nor removed — listed apart, and
/// never part of the verdict.
public struct UnobservableDeclaration: Sendable, Codable, Equatable {
    /// One side of a diff.
    public enum Side: String, Sendable, Codable, Equatable {
        case old
        case new
    }

    /// The side whose image cannot show the declaration.
    public let side: Side
    /// The container's identity, or the member's.
    public let key: ABIKey
    /// The container's name — for a member, its container's; `nil` for a
    /// global.
    public let containerName: String?
    /// The container's kind — for a member, its container's; `nil` for a
    /// global.
    public let containerKind: ContainerKind?
    /// The member's kind; `nil` when the declaration is a container.
    public let memberKind: MemberKind?
    /// The member's rendering from the side that shows it, or the
    /// container's name.
    public let signature: String

    public init(
        side: Side,
        key: ABIKey,
        containerName: String?,
        containerKind: ContainerKind?,
        memberKind: MemberKind?,
        signature: String
    ) {
        self.side = side
        self.key = key
        self.containerName = containerName
        self.containerKind = containerKind
        self.memberKind = memberKind
        self.signature = signature
    }
}
