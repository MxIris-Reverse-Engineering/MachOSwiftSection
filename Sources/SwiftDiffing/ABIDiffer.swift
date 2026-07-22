import Demangling
import OrderedCollections
import SwiftDeclaration

/// Diffs the Swift ABI of two indexed modules by keying every declaration on
/// its remangled `Node` and computing a recursive three-way set difference.
///
/// Synchronous and Mach-O-free: it operates purely on the (already-indexed)
/// `SwiftDeclaration` model. Build the two `ABIModule` inputs from two prepared
/// indexers, then call ``diff(old:new:)``. It walks every category the indexer
/// classifies — types, protocols, the four extension buckets, and globals —
/// reusing one generic matcher. Output arrays are sorted deterministically.
public struct ABIDiffer: Sendable {
    public init() {}

    // MARK: - Top level

    /// Diff two live modules. Equivalent to freezing both into snapshots and
    /// diffing those — the two entry points share one algorithm, so a live diff
    /// and a baseline diff can never disagree.
    public func diff(old: ABIModule, new: ABIModule) -> ABIDiff {
        diff(old: snapshot(of: old), new: snapshot(of: new))
    }

    /// Diff two persisted baselines, carrying each document's provenance onto
    /// the result so reports can name the binaries they describe.
    public func diff(old: ABISnapshotDocument, new: ABISnapshotDocument) -> ABIDiff {
        diff(
            old: old.snapshot,
            new: new.snapshot,
            oldProvenance: old.provenance,
            newProvenance: new.provenance
        )
    }

    /// Diff two frozen snapshots. Pure value-data computation — no model, no
    /// Mach-O — so it is fully unit-testable and runs against persisted
    /// baselines. The optional provenances are stamped onto the result verbatim
    /// (they never affect the comparison).
    public func diff(
        old: ABISnapshot,
        new: ABISnapshot,
        oldProvenance: ABIProvenance? = nil,
        newProvenance: ABIProvenance? = nil
    ) -> ABIDiff {
        let oldSideKeyCollisions = old.keyCollisions()
        let newSideKeyCollisions = new.keyCollisions()
        let diagnostics = (oldSideKeyCollisions.isEmpty && newSideKeyCollisions.isEmpty)
            ? nil
            : ABIDiffDiagnostics(oldSideKeyCollisions: oldSideKeyCollisions, newSideKeyCollisions: newSideKeyCollisions)
        return ABIDiff(
            types: diffContainerSnapshots(old.types, new.types),
            protocols: diffContainerSnapshots(old.protocols, new.protocols),
            typeExtensions: diffContainerSnapshots(old.typeExtensions, new.typeExtensions),
            protocolExtensions: diffContainerSnapshots(old.protocolExtensions, new.protocolExtensions),
            typeAliasExtensions: diffContainerSnapshots(old.typeAliasExtensions, new.typeAliasExtensions),
            conformanceExtensions: diffContainerSnapshots(old.conformanceExtensions, new.conformanceExtensions),
            globalVariables: diffMembers(old: old.globalVariables, new: new.globalVariables),
            globalFunctions: diffMembers(old: old.globalFunctions, new: new.globalFunctions),
            oldProvenance: oldProvenance,
            newProvenance: newProvenance,
            diagnostics: diagnostics
        )
    }

    // MARK: - Freeze (ABIModule -> ABISnapshot)

    /// Freeze a live, Mach-O-coupled module into a persistable snapshot by
    /// projecting every declaration into its diff records. All of the model
    /// knowledge lives here; the diff above is then pure data over the result.
    public func snapshot(of module: ABIModule) -> ABISnapshot {
        ABISnapshot(
            types: containerSnapshots(
                Array(module.allTypeDefinitions.values),
                containerKind: .type,
                key: { ABIKey.makeUnwrappingType(for: $0.typeName.node) },
                name: { $0.typeName.name(using: .default) },
                members: { self.memberRecords(of: $0) }
            ),
            protocols: containerSnapshots(
                Array(module.allProtocolDefinitions.values),
                containerKind: .protocol,
                key: { ABIKey.makeUnwrappingType(for: $0.protocolName.node) },
                name: { $0.protocolName.name(using: .default) },
                members: { self.memberRecords(of: $0) }
            ),
            typeExtensions: extensionBucketSnapshots(module.typeExtensionDefinitions, .typeExtension),
            protocolExtensions: extensionBucketSnapshots(module.protocolExtensionDefinitions, .protocolExtension),
            typeAliasExtensions: extensionBucketSnapshots(module.typeAliasExtensionDefinitions, .typeAliasExtension),
            conformanceExtensions: extensionBucketSnapshots(module.conformanceExtensionDefinitions, .conformanceExtension),
            globalVariables: module.globalVariableDefinitions.map(MemberRecord.make),
            globalFunctions: module.globalFunctionDefinitions.map(MemberRecord.make)
        )
    }

    private func containerSnapshots<Container>(
        _ containers: [Container],
        containerKind: ContainerKind,
        key: (Container) -> ABIKey,
        name: (Container) -> String,
        members: (Container) -> [MemberRecord]
    ) -> [ContainerSnapshot] {
        containers.map { ContainerSnapshot(key: key($0), name: name($0), kind: containerKind, members: members($0)) }
    }

    /// One indexer extension bucket maps an `ExtensionName` (target + kind) to
    /// *many* `ExtensionDefinition`s — the indexer splits a type's
    /// conformances, conditional blocks, and synthetic nested-type blocks into
    /// separate definitions filed under one name. We freeze one
    /// `ContainerSnapshot` per `ExtensionName`, **merging the member records
    /// across every definition in the bucket**: the extension boundary itself
    /// is not exported, only the members (and the witness members of
    /// conformances) are. Merging makes adding/removing a whole conformance
    /// visible and avoids the silent-drop collisions that per-definition keying
    /// suffered when two definitions on one target shared an identity.
    ///
    /// TODO(P2): per-conformance / per-`where`-block attribution — needs the
    /// indexer to plumb the resolved protocol name onto each definition.
    private func extensionBucketSnapshots(
        _ buckets: OrderedDictionary<ExtensionName, [ExtensionDefinition]>,
        _ containerKind: ContainerKind
    ) -> [ContainerSnapshot] {
        buckets.map { name, definitions in
            ContainerSnapshot(
                key: extensionBucketKey(name),
                name: name.name(using: .default),
                kind: containerKind,
                members: definitions.flatMap { self.memberRecords(of: $0) }
            )
        }
    }

    // MARK: - Snapshot diff (ABISnapshot -> ABIDiff)

    /// Match container snapshots by key, then diff each matched pair's members.
    /// One helper serves every axis — types, protocols, and all four extension
    /// buckets — since they are all `[ContainerSnapshot]` once frozen.
    private func diffContainerSnapshots(_ old: [ContainerSnapshot], _ new: [ContainerSnapshot]) -> [ContainerChange] {
        let matched = threeWayMatch(old: old, new: new) { $0.key }

        var changes: [ContainerChange] = []
        changes.append(contentsOf: matched.removed.map {
            ContainerChange(key: $0.key, name: $0.name, containerKind: $0.kind, status: .removed, memberChanges: [])
        })
        changes.append(contentsOf: matched.added.map {
            ContainerChange(key: $0.key, name: $0.name, containerKind: $0.kind, status: .added, memberChanges: [])
        })
        for (oldContainer, newContainer) in matched.common {
            let memberChanges = diffMembers(old: oldContainer.members, new: newContainer.members)
            if !memberChanges.isEmpty {
                changes.append(ContainerChange(
                    key: newContainer.key,
                    name: newContainer.name,
                    containerKind: newContainer.kind,
                    status: .modified,
                    memberChanges: memberChanges
                ))
            }
        }
        return sorted(changes, key: \.key, status: \.status)
    }

    /// Identity for an extension bucket: the target node plus an explicit kind
    /// token, so `extension`s on a struct vs a class of the same name (or the
    /// four extension kinds) stay distinct.
    private func extensionBucketKey(_ name: ExtensionName) -> ABIKey {
        Self.extensionBucketKey(for: name)
    }

    /// The same bucket identity, exposed so the diffable-interface renderer can
    /// match extension buckets across the two binaries with the exact key the
    /// differ uses (one source of truth — no drift between the verdict and the
    /// annotated interface).
    public static func extensionBucketKey(for name: ExtensionName) -> ABIKey {
        .printed("extbucket:\(extensionKindToken(name.kind))|\(ABIKey.makeUnwrappingType(for: name.node).sortKey)")
    }

    /// Stable token per extension kind — an explicit switch rather than
    /// `String(describing:)` reflection, so identity is injective by code.
    static func extensionKindToken(_ kind: ExtensionKind) -> String {
        switch kind {
        case .type(.struct): return "struct"
        case .type(.class): return "class"
        case .type(.enum): return "enum"
        case .protocol: return "protocol"
        case .typeAlias: return "typeAlias"
        }
    }

    // MARK: - Member projection

    /// Projects the eight member collections every `Definition` shares (types,
    /// protocols, and extensions all expose them). The kind-specific extras —
    /// stored fields / enum cases / `deinit` for types, associated types for
    /// protocols — are layered on by the concrete overloads below.
    func sharedMemberRecords(of definition: some Definition) -> [MemberRecord] {
        var records: [MemberRecord] = []
        records.append(contentsOf: definition.variables.map(MemberRecord.make))
        records.append(contentsOf: definition.staticVariables.map(MemberRecord.make))
        records.append(contentsOf: definition.functions.map(MemberRecord.make))
        records.append(contentsOf: definition.staticFunctions.map(MemberRecord.make))
        records.append(contentsOf: definition.subscripts.map(MemberRecord.make))
        records.append(contentsOf: definition.staticSubscripts.map(MemberRecord.make))
        records.append(contentsOf: definition.allocators.map(MemberRecord.make))
        records.append(contentsOf: definition.constructors.map(MemberRecord.make))
        return records
    }

    /// A type adds stored fields (or order-sensitive enum cases) and `deinit`
    /// on top of the shared members.
    func memberRecords(of definition: TypeDefinition) -> [MemberRecord] {
        var records = sharedMemberRecords(of: definition)
        if case .enum = definition.type {
            for (tag, field) in definition.fields.enumerated() {
                records.append(.makeCase(field, tag: tag))
            }
        } else {
            records.append(contentsOf: definition.fields.map(MemberRecord.make))
        }
        if definition.hasDeallocator {
            records.append(.makeDeinit())
        }
        return records
    }

    /// A protocol adds its associated-type requirements on top of the shared
    /// members. TODO(P2): project `strippedSymbolicRequirements` (unresolved
    /// witness-table slots) — keyed on pwtOffset + flags; needs the
    /// MachOSwiftSection `ProtocolRequirement` type.
    func memberRecords(of definition: ProtocolDefinition) -> [MemberRecord] {
        var records = sharedMemberRecords(of: definition)
        records.append(contentsOf: definition.associatedTypes.map(MemberRecord.makeAssociatedType))
        return records
    }

    /// An extension contributes only its shared members for now. TODO(P2):
    /// conformance-extension associated-type witnesses — `associatedTypes` is
    /// `[MachOSwiftSection.AssociatedType]` whose name accessors are Mach-O-
    /// bound, so it cannot be projected Mach-O-free here.
    func memberRecords(of definition: ExtensionDefinition) -> [MemberRecord] {
        sharedMemberRecords(of: definition)
    }

    // MARK: - Member level (test seam)

    /// Three-way set difference over member records, keyed by `identityKey`.
    /// Public so it can be unit-tested without constructing a `Definition`
    /// (whose initializers need a Mach-O).
    public func diffMembers(old: [MemberRecord], new: [MemberRecord]) -> [MemberChange] {
        let matched = threeWayMatch(old: old, new: new) { $0.identityKey }

        var changes: [MemberChange] = []
        changes.append(contentsOf: matched.removed.map {
            MemberChange(key: $0.identityKey, kind: $0.kind, status: .removed, oldSignature: $0.signature, newSignature: nil)
        })
        changes.append(contentsOf: matched.added.map {
            MemberChange(key: $0.identityKey, kind: $0.kind, status: .added, oldSignature: nil, newSignature: $0.signature)
        })
        for (oldRecord, newRecord) in matched.common where oldRecord.payloadKey != newRecord.payloadKey {
            changes.append(MemberChange(key: newRecord.identityKey, kind: newRecord.kind, status: .modified, oldSignature: oldRecord.signature, newSignature: newRecord.signature))
        }
        return sorted(changes, key: \.key, status: \.status)
    }

    // MARK: - Generic primitives

    /// The single three-way matcher every diff axis specializes: index both
    /// sides by `identity`, then partition into old-only (`removed`), new-only
    /// (`added`), and present-on-both (`common`, as old/new pairs). Callers
    /// decide how to compare each `common` pair.
    private func threeWayMatch<Element>(
        old: [Element],
        new: [Element],
        identity: (Element) -> ABIKey
    ) -> (removed: [Element], added: [Element], common: [(old: Element, new: Element)]) {
        let oldByKey = keyedFirstWins(old, by: identity)
        let newByKey = keyedFirstWins(new, by: identity)

        var removed: [Element] = []
        var added: [Element] = []
        var common: [(old: Element, new: Element)] = []

        for (elementKey, element) in oldByKey {
            if let match = newByKey[elementKey] {
                common.append((old: element, new: match))
            } else {
                removed.append(element)
            }
        }
        for (elementKey, element) in newByKey where oldByKey[elementKey] == nil {
            added.append(element)
        }

        return (removed, added, common)
    }

    /// Deterministic ordering by key string then status, so repeated runs over
    /// the same inputs produce identical output.
    private func sorted<Change>(_ changes: [Change], key: (Change) -> ABIKey, status: (Change) -> ChangeStatus) -> [Change] {
        changes.sorted { lhs, rhs in
            (key(lhs).sortKey, status(lhs).sortRank) < (key(rhs).sortKey, status(rhs).sortRank)
        }
    }
}
