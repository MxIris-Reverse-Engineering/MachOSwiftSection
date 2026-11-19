/// A frozen, `Codable` projection of an `ABIModule` — the diff currency for
/// persistence.
///
/// An `ABIModule` holds the live, Mach-O-coupled `*Definition` model (which is
/// not serializable: it carries descriptor/metadata handles meaningful only to
/// one binary, plus a reference cycle). An `ABISnapshot` is the same
/// declarations *frozen* into pure value data — exactly the keys and signatures
/// the differ compares — so a binary's ABI can be stored as a baseline and
/// diffed later **without** the original binary.
///
/// Build one with `ABIDiffer().snapshot(of: module)`, persist via `Codable`,
/// and diff two snapshots with `ABIDiffer().diff(old:new:)`. The live
/// `diff(old: ABIModule, new: ABIModule)` is exactly "freeze both, diff the
/// snapshots", so the two entry points share one algorithm.
///
/// Buckets mirror `ABIModule` / the indexer classification one-for-one.
public struct ABISnapshot: Codable, Equatable, Sendable {
    public var types: [ContainerSnapshot]
    public var protocols: [ContainerSnapshot]
    public var typeExtensions: [ContainerSnapshot]
    public var protocolExtensions: [ContainerSnapshot]
    public var typeAliasExtensions: [ContainerSnapshot]
    public var conformanceExtensions: [ContainerSnapshot]
    public var globalVariables: [MemberRecord]
    public var globalFunctions: [MemberRecord]
    // TODO(P2): a versioned header — the member key strings ("field:", "tag:",
    // "…|acc:…") are the de-facto format, so a key-scheme bump must invalidate
    // old snapshots.

    /// Whether the image this snapshot was frozen from carries any local
    /// (non-external) Swift symbol. `false` for an image stripped of its
    /// local symbols — SwiftUI in the macOS 13.0–14.8 dyld shared caches —
    /// which shows only its exported Swift names: a member whose only
    /// evidence is a non-exported symbol cannot be seen there, so a
    /// comparison treats its absence as unobservable rather than as a
    /// removal (evolution proposal `evolution-unobservable-presence`).
    public var hasLocalSwiftSymbols: Bool

    public init(
        types: [ContainerSnapshot] = [],
        protocols: [ContainerSnapshot] = [],
        typeExtensions: [ContainerSnapshot] = [],
        protocolExtensions: [ContainerSnapshot] = [],
        typeAliasExtensions: [ContainerSnapshot] = [],
        conformanceExtensions: [ContainerSnapshot] = [],
        globalVariables: [MemberRecord] = [],
        globalFunctions: [MemberRecord] = [],
        hasLocalSwiftSymbols: Bool = true
    ) {
        self.types = types
        self.protocols = protocols
        self.typeExtensions = typeExtensions
        self.protocolExtensions = protocolExtensions
        self.typeAliasExtensions = typeAliasExtensions
        self.conformanceExtensions = conformanceExtensions
        self.globalVariables = globalVariables
        self.globalFunctions = globalFunctions
        self.hasLocalSwiftSymbols = hasLocalSwiftSymbols
    }
}

/// One frozen container (type / protocol / extension sub-bucket): its identity
/// key, reporting name, kind, and the projected member records the differ
/// compares.
///
/// Extension containers are keyed per **(target, protocol, where clause,
/// retroactive)** — one conformance / conditional block per container — so a
/// conformance appearing or disappearing is a container-level change and two
/// conditional blocks never share a member keying scope. The structured
/// `conformedProtocolName` / `whereClauseText` fields carry the attribution
/// for reporting (the display `name` already embeds them).
public struct ContainerSnapshot: Codable, Equatable, Sendable {
    public var key: ABIKey
    public var name: String
    public var kind: ContainerKind
    /// The conformed protocol's qualified name; extension containers of a
    /// conformance only.
    public var conformedProtocolName: String?
    /// The conditional-conformance / constrained-extension `where` clause,
    /// printed; `nil` for unconstrained containers.
    public var whereClauseText: String?
    public var members: [MemberRecord]

    public init(
        key: ABIKey,
        name: String,
        kind: ContainerKind,
        conformedProtocolName: String? = nil,
        whereClauseText: String? = nil,
        members: [MemberRecord]
    ) {
        self.key = key
        self.name = name
        self.kind = kind
        self.conformedProtocolName = conformedProtocolName
        self.whereClauseText = whereClauseText
        self.members = members
    }
}
