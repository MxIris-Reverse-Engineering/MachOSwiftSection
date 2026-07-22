/// The three-valued lattice every diff entity lives in, shared by all levels
/// (containers, members) so the vocabulary stays consistent.
public enum ChangeStatus: Sendable, Codable, Equatable {
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
public enum MemberKind: Sendable, Codable, Equatable {
    case function
    case allocator
    case constructor
    case variable
    case `subscript`
    case `deinit`
    case enumCase
    case field
    /// A protocol's associated-type *requirement* (its existence shapes the
    /// witness table).
    case associatedType
    /// A conformance's associated-type *witness* (which type was bound).
    case associatedTypeWitness
    /// A protocol requirement whose symbol was stripped — visible only as a
    /// witness-table slot (keyed on its PWT offset, flags in the payload).
    case protocolRequirement
}

/// Which container a `ContainerChange` describes — keeps types, protocols and
/// the four extension buckets distinguishable in a single change type.
public enum ContainerKind: Sendable, Codable, Equatable {
    case type
    case `protocol`
    case typeExtension
    case protocolExtension
    case typeAliasExtension
    case conformanceExtension
}

/// One member-level delta within a container.
///
/// `status` is derived from identity matching on `ABIKey`:
/// - `.added` / `.removed` — the member's identity exists on only one side.
/// - `.modified` — the identity matches on both sides but the comparable
///   payload differs (e.g. a stored field keeps its name but changes type, or
///   a property gains a setter). Members keyed by their full mangled signature
///   never report `.modified` — a signature change is a different symbol, so it
///   surfaces as `.removed` + `.added`.
public struct MemberChange: Sendable, Codable, Equatable {
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

/// One container-level delta — a type, a protocol, or an extension.
///
/// - `.added` / `.removed` — the container exists on only one side;
///   `memberChanges` is left empty (the whole container is the change).
/// - `.modified` — the container exists on both sides and at least one member
///   changed; `memberChanges` carries the per-member deltas.
///
/// Container-level non-member payload (an extension's generic constraints or
/// `@retroactive`, a type's struct↔class kind) is folded into the container's
/// `ABIKey` identity, so such a change surfaces as `.removed` + `.added` rather
/// than a separate metadata field.
public struct ContainerChange: Sendable, Codable, Equatable {
    public let key: ABIKey
    /// The container's qualified demangled name, for reporting.
    public let name: String
    public let containerKind: ContainerKind
    public let status: ChangeStatus
    public let memberChanges: [MemberChange]

    public init(
        key: ABIKey,
        name: String,
        containerKind: ContainerKind,
        status: ChangeStatus,
        memberChanges: [MemberChange]
    ) {
        self.key = key
        self.name = name
        self.containerKind = containerKind
        self.status = status
        self.memberChanges = memberChanges
    }
}

/// The structured result of diffing two `ABIModule`s.
///
/// Buckets mirror `SwiftDeclarationIndexer`'s definition classification so no
/// granularity is lost. A pure value type (no Mach-O, no model references) — it
/// is `Codable` and `Equatable`, so a diff can be persisted as an ABI baseline
/// and two diffs compared directly. All arrays are sorted deterministically (by
/// key then status), so encoding the same diff twice is byte-stable.
public struct ABIDiff: Sendable, Codable, Equatable {
    public let types: [ContainerChange]
    public let protocols: [ContainerChange]
    public let typeExtensions: [ContainerChange]
    public let protocolExtensions: [ContainerChange]
    public let typeAliasExtensions: [ContainerChange]
    public let conformanceExtensions: [ContainerChange]
    public let globalVariables: [MemberChange]
    public let globalFunctions: [MemberChange]
    /// Where the old side came from, when known. Descriptive metadata for
    /// reports only — never part of the diff computation or of `isEmpty`.
    public let oldProvenance: ABIProvenance?
    /// Where the new side came from, when known.
    public let newProvenance: ABIProvenance?
    /// What the comparison had to resolve silently (identity-key collisions),
    /// `nil` when nothing. Not part of `isEmpty` — a clean diff with
    /// collisions still warns, because a dropped record can hide a change.
    public let diagnostics: ABIDiffDiagnostics?

    public init(
        types: [ContainerChange] = [],
        protocols: [ContainerChange] = [],
        typeExtensions: [ContainerChange] = [],
        protocolExtensions: [ContainerChange] = [],
        typeAliasExtensions: [ContainerChange] = [],
        conformanceExtensions: [ContainerChange] = [],
        globalVariables: [MemberChange] = [],
        globalFunctions: [MemberChange] = [],
        oldProvenance: ABIProvenance? = nil,
        newProvenance: ABIProvenance? = nil,
        diagnostics: ABIDiffDiagnostics? = nil
    ) {
        self.types = types
        self.protocols = protocols
        self.typeExtensions = typeExtensions
        self.protocolExtensions = protocolExtensions
        self.typeAliasExtensions = typeAliasExtensions
        self.conformanceExtensions = conformanceExtensions
        self.globalVariables = globalVariables
        self.globalFunctions = globalFunctions
        self.oldProvenance = oldProvenance
        self.newProvenance = newProvenance
        self.diagnostics = diagnostics
    }

    public var isEmpty: Bool {
        types.isEmpty && protocols.isEmpty
            && typeExtensions.isEmpty && protocolExtensions.isEmpty
            && typeAliasExtensions.isEmpty && conformanceExtensions.isEmpty
            && globalVariables.isEmpty && globalFunctions.isEmpty
    }
}
