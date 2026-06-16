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

    public init(
        types: [ContainerSnapshot] = [],
        protocols: [ContainerSnapshot] = [],
        typeExtensions: [ContainerSnapshot] = [],
        protocolExtensions: [ContainerSnapshot] = [],
        typeAliasExtensions: [ContainerSnapshot] = [],
        conformanceExtensions: [ContainerSnapshot] = [],
        globalVariables: [MemberRecord] = [],
        globalFunctions: [MemberRecord] = []
    ) {
        self.types = types
        self.protocols = protocols
        self.typeExtensions = typeExtensions
        self.protocolExtensions = protocolExtensions
        self.typeAliasExtensions = typeAliasExtensions
        self.conformanceExtensions = conformanceExtensions
        self.globalVariables = globalVariables
        self.globalFunctions = globalFunctions
    }
}

/// One frozen container (type / protocol / extension bucket): its identity key,
/// reporting name, kind, and the projected member records the differ compares.
public struct ContainerSnapshot: Codable, Equatable, Sendable {
    public var key: ABIKey
    public var name: String
    public var kind: ContainerKind
    public var members: [MemberRecord]

    public init(key: ABIKey, name: String, kind: ContainerKind, members: [MemberRecord]) {
        self.key = key
        self.name = name
        self.kind = kind
        self.members = members
    }
}
