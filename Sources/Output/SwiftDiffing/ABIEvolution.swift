/// One position on an evolution's ordered version axis.
public struct ABIVersionDescriptor: Sendable, Codable, Equatable {
    /// The human-readable axis name (e.g. `"17.0"`). Always present — resolved
    /// by `ABIEvolutionBuilder` from explicit labels, snapshot provenance, or a
    /// positional fallback.
    public let label: String
    public let provenance: ABIProvenance?

    public init(label: String, provenance: ABIProvenance? = nil) {
        self.label = label
        self.provenance = provenance
    }
}

/// One transition on a lineage: what happened between the *previous* version
/// and `versions[versionIndex]`.
///
/// `versionIndex` is always ≥ 1 — an event at index `i` describes the
/// `versions[i-1] → versions[i]` step. Presence at the first version is not an
/// event; it is the lineage's `presence[0]` baseline.
///
/// An event can also span versions that cannot show the declaration (see
/// ``LineagePresenceState/unobservable``): then `earliestVersionIndex` names
/// the first of them, the change happened at some version from there through
/// `versionIndex`, and `versionIndex` is where it was first observed.
public struct LineageEvent: Sendable, Codable, Equatable {
    public let versionIndex: Int
    public let status: ChangeStatus
    /// Human-readable rendering on the pre-transition side, when present.
    public let oldSignature: String?
    /// Human-readable rendering on the post-transition side, when present.
    public let newSignature: String?
    /// Record-level verdict refinement, same rule as
    /// `MemberChange.compatibilityOverride` (shared via
    /// `MemberRecord.compatibilityOverride(old:new:)`); `nil` means the plain
    /// status rule applies. Always `nil` on container-level events.
    public let compatibilityOverride: Compatibility?
    /// For an event placed only between two observations (evolution
    /// proposal `evolution-unobservable-presence`): the earliest version it
    /// may have happened at — the first of the versions in between, none of
    /// which could show the declaration. `nil` for an event placed exactly,
    /// at `versionIndex`.
    public let earliestVersionIndex: Int?

    public init(
        versionIndex: Int,
        status: ChangeStatus,
        oldSignature: String? = nil,
        newSignature: String? = nil,
        compatibilityOverride: Compatibility? = nil,
        earliestVersionIndex: Int? = nil
    ) {
        self.versionIndex = versionIndex
        self.status = status
        self.oldSignature = oldSignature
        self.newSignature = newSignature
        self.compatibilityOverride = compatibilityOverride
        self.earliestVersionIndex = earliestVersionIndex
    }
}

/// What one version of the axis shows of a lineage (evolution proposal
/// `evolution-unobservable-presence`). A version whose image carries no
/// local Swift symbols cannot show a member that only a non-exported symbol
/// evidences, so its absence there is not an observation; the versions
/// around such a span decide what is inferred inside it.
public enum LineagePresenceState: String, Sendable, Codable, Equatable {
    /// The version shows the declaration.
    case present
    /// The version would show the declaration and does not.
    case absent
    /// The version cannot show the declaration, and the nearest observations
    /// on both sides found it present: inferred present.
    case inferredPresent
    /// The version cannot show the declaration, and its neighbours do not
    /// both find it present — they disagree (an event spans the gap), both
    /// find it absent, or the axis ends first.
    case unobservable

    /// Whether this state was seen rather than inferred or unknown.
    public var isObserved: Bool {
        self == .present || self == .absent
    }
}

/// The lifeline of one member identity across the version axis.
///
/// Only lineages with at least one event are materialized — an API that never
/// changes never appears, mirroring `ABIDiff`'s "changes only" contract — and
/// lineages of members some version cannot show while it shows their
/// container, when that span says something (inferred present, or a bound
/// left unknown), so a reader learns which versions said nothing about them.
/// A member unseen only where its container is unseen is the container's
/// story, as the members of an added or removed container are.
public struct MemberLineage: Sendable, Codable, Equatable {
    public let key: ABIKey
    public let kind: MemberKind
    /// Per-version existence, one entry per version on the axis — observed or
    /// inferred (``LineagePresenceState/inferredPresent``). For a member of
    /// a container this means "container present AND member present", so a
    /// container-level disappearance turns every member's bit off too.
    public let presence: [Bool]
    /// Adjacent-version transitions, ordered by `versionIndex`. Member events
    /// exist only for transitions where the owning container is present on
    /// both sides — when the container itself appears/disappears, the
    /// container's own event is the change (same rule as `ABIDiff`, whose
    /// added/removed containers carry no `memberChanges`).
    public let events: [LineageEvent]
    /// What each version shows of the member, when some version cannot show
    /// it; `nil` when every version was observed and `presence` is the whole
    /// story (evolution proposal `evolution-unobservable-presence`).
    public let presenceStates: [LineagePresenceState]?
    /// The member's rendering from the latest version that shows it, carried
    /// only by a lineage without events — one materialized for its
    /// unobservable versions alone — since an event otherwise carries it.
    public let latestSignature: String?

    public init(
        key: ABIKey,
        kind: MemberKind,
        presence: [Bool],
        events: [LineageEvent],
        presenceStates: [LineagePresenceState]? = nil,
        latestSignature: String? = nil
    ) {
        self.key = key
        self.kind = kind
        self.presence = presence
        self.events = events
        self.presenceStates = presenceStates
        self.latestSignature = latestSignature
    }
}

/// The lifeline of one container (type / protocol / extension bucket) across
/// the version axis.
public struct ContainerLineage: Sendable, Codable, Equatable {
    public let key: ABIKey
    /// The container's qualified demangled name, taken from its latest
    /// appearance on the axis.
    public let name: String
    public let containerKind: ContainerKind
    /// Per-version existence, one entry per version on the axis — observed or
    /// inferred (``LineagePresenceState/inferredPresent``).
    public let presence: [Bool]
    /// Container-level presence transitions only (`.added` / `.removed`).
    /// "Modified at version i" is not a container event — it is derivable as
    /// "has a member event at i", so it is not stored twice.
    public let events: [LineageEvent]
    /// Member lifelines with at least one event or an unobservable version,
    /// sorted by key.
    public let memberLineages: [MemberLineage]
    /// What each version shows of the container, when some version cannot
    /// show it — an extension only non-exported members make up, in a
    /// version without local Swift symbols; `nil` when every version was
    /// observed (evolution proposal `evolution-unobservable-presence`).
    public let presenceStates: [LineagePresenceState]?

    public init(
        key: ABIKey,
        name: String,
        containerKind: ContainerKind,
        presence: [Bool],
        events: [LineageEvent],
        memberLineages: [MemberLineage],
        presenceStates: [LineagePresenceState]? = nil
    ) {
        self.key = key
        self.name = name
        self.containerKind = containerKind
        self.presence = presence
        self.events = events
        self.memberLineages = memberLineages
        self.presenceStates = presenceStates
    }
}

/// The structured result of tracking one module's ABI across N ≥ 2 ordered
/// versions — the N-way generalization of `ABIDiff`.
///
/// Buckets mirror `ABIDiff` one-for-one. A pure value type (`Codable` +
/// `Equatable`), deterministically sorted, so an evolution can be persisted
/// and two evolutions compared directly. For N == 2 the events at
/// `versionIndex == 1` correspond exactly to `ABIDiffer.diff(old:new:)`'s
/// changes — the two paths cannot disagree.
public struct ABIEvolution: Sendable, Codable, Equatable {
    /// The ordered version axis every `presence` array and `versionIndex`
    /// refers into.
    public let versions: [ABIVersionDescriptor]
    public let types: [ContainerLineage]
    public let protocols: [ContainerLineage]
    public let typeExtensions: [ContainerLineage]
    public let protocolExtensions: [ContainerLineage]
    public let typeAliasExtensions: [ContainerLineage]
    public let conformanceExtensions: [ContainerLineage]
    public let globalVariables: [MemberLineage]
    public let globalFunctions: [MemberLineage]
    /// Identity-key collisions per version (one entry per version on the
    /// axis, aligned with `versions`), `nil` when no version has any. A
    /// collision means first-wins keying dropped a record there, so that
    /// version's transitions can be quietly weaker than reported — the
    /// reporters surface these as warnings.
    public let keyCollisionsByVersion: [[ABIKeyCollision]]?
    /// Remangle-fallback keys per version (aligned with `versions`), `nil`
    /// when no version has any. A fallback key is deterministic but
    /// remangle-success-dependent, so a cross-toolchain axis can flip an
    /// identity `.mangled`↔`.printed` — the reporters surface these as
    /// warnings (see `ABIRemangleFallback`).
    public let remangleFallbacksByVersion: [[ABIRemangleFallback]]?
    /// The versions whose image carries no local Swift symbols, ascending, or
    /// `nil` when every version has them. Such a version cannot show a
    /// member only a non-exported symbol evidences (evolution proposal
    /// `evolution-unobservable-presence`).
    public let versionIndicesWithoutLocalSwiftSymbols: [Int]?

    public init(
        versions: [ABIVersionDescriptor],
        types: [ContainerLineage] = [],
        protocols: [ContainerLineage] = [],
        typeExtensions: [ContainerLineage] = [],
        protocolExtensions: [ContainerLineage] = [],
        typeAliasExtensions: [ContainerLineage] = [],
        conformanceExtensions: [ContainerLineage] = [],
        globalVariables: [MemberLineage] = [],
        globalFunctions: [MemberLineage] = [],
        keyCollisionsByVersion: [[ABIKeyCollision]]? = nil,
        remangleFallbacksByVersion: [[ABIRemangleFallback]]? = nil,
        versionIndicesWithoutLocalSwiftSymbols: [Int]? = nil
    ) {
        self.versions = versions
        self.types = types
        self.protocols = protocols
        self.typeExtensions = typeExtensions
        self.protocolExtensions = protocolExtensions
        self.typeAliasExtensions = typeAliasExtensions
        self.conformanceExtensions = conformanceExtensions
        self.globalVariables = globalVariables
        self.globalFunctions = globalFunctions
        self.keyCollisionsByVersion = keyCollisionsByVersion
        self.remangleFallbacksByVersion = remangleFallbacksByVersion
        self.versionIndicesWithoutLocalSwiftSymbols = versionIndicesWithoutLocalSwiftSymbols
    }

    public var allContainerLineages: [ContainerLineage] {
        types + protocols + typeExtensions + protocolExtensions + typeAliasExtensions + conformanceExtensions
    }

    public var allGlobalLineages: [MemberLineage] {
        globalVariables + globalFunctions
    }

    /// `true` when nothing changed anywhere across the whole axis.
    public var isEmpty: Bool {
        allContainerLineages.isEmpty && allGlobalLineages.isEmpty
    }
}
