/// The three-valued lattice every diff entity lives in, shared by all levels
/// (types, members, and the P2 axes) so the vocabulary stays consistent.
public enum ChangeStatus: Sendable {
    /// Present only on the new side.
    case added
    /// Present only on the old side.
    case removed
    /// Matched on both sides under the same identity, but the comparable
    /// payload differs.
    case modified
}

extension ChangeStatus {
    /// Stable ordering rank, used to make diff output deterministic.
    var sortRank: Int {
        switch self {
        case .removed: return 0
        case .added: return 1
        case .modified: return 2
        }
    }
}

/// The kind of a diffed member, used for reporting and to keep members of
/// different kinds in distinct identity namespaces.
public enum MemberKind: Sendable {
    case function
    case allocator
    case constructor
    case variable
    case `subscript`
    case `deinit`
    case enumCase
    case field
}

/// One member-level delta within a type.
///
/// `status` is derived from identity matching on `ABIKey`:
/// - `.added` / `.removed` — the member's identity exists on only one side.
/// - `.modified` — the identity matches on both sides but the comparable
///   payload differs (e.g. a stored field keeps its name but changes type, or
///   a property gains a setter). Members keyed by their full mangled signature
///   never report `.modified` — a signature change is a different symbol, so it
///   surfaces as `.removed` + `.added`.
public struct MemberChange: Sendable {
    public let key: ABIKey
    public let kind: MemberKind
    public let status: ChangeStatus
    /// Human-readable rendering of the old member, when present.
    public let oldSignature: String?
    /// Human-readable rendering of the new member, when present.
    public let newSignature: String?

    public init(
        key: ABIKey,
        kind: MemberKind,
        status: ChangeStatus,
        oldSignature: String?,
        newSignature: String?
    ) {
        self.key = key
        self.kind = kind
        self.status = status
        self.oldSignature = oldSignature
        self.newSignature = newSignature
    }
}

/// One type-level delta.
///
/// - `.added` / `.removed` — the type exists on only one side; `memberChanges`
///   is left empty (the whole type is the change).
/// - `.modified` — the type exists on both sides and at least one member
///   changed; `memberChanges` carries the per-member deltas.
public struct TypeChange: Sendable {
    public let key: ABIKey
    /// The type's qualified demangled name, for reporting.
    public let name: String
    public let status: ChangeStatus
    public let memberChanges: [MemberChange]

    public init(key: ABIKey, name: String, status: ChangeStatus, memberChanges: [MemberChange]) {
        self.key = key
        self.name = name
        self.status = status
        self.memberChanges = memberChanges
    }
}

/// The structured result of diffing two `ABIModule`s.
///
/// A pure value type (no Mach-O, no model references), so it is `Codable`-ready
/// in P2 and can be persisted as an ABI baseline. The arrays are sorted
/// deterministically (by key then status) so two runs over the same inputs
/// produce byte-identical output.
public struct ABIDiff: Sendable {
    public let types: [TypeChange]
    // TODO(P2): protocols: [TypeChange]-shaped ProtocolChange
    // TODO(P2): extensions, globals
    // TODO(P2): provenance header (old/new binary identity + version) for reports

    public init(types: [TypeChange]) {
        self.types = types
    }

    public var isEmpty: Bool { types.isEmpty }
}
