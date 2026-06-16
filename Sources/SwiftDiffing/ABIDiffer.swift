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

    public func diff(old: ABIModule, new: ABIModule) -> ABIDiff {
        ABIDiff(
            types: diffContainers(
                old: Array(old.allTypeDefinitions.values),
                new: Array(new.allTypeDefinitions.values),
                containerKind: .type,
                identity: { ABIKey.makeUnwrappingType(for: $0.typeName.node) },
                name: { $0.typeName.name },
                members: { self.memberRecords(of: $0) }
            ),
            protocols: diffContainers(
                old: Array(old.allProtocolDefinitions.values),
                new: Array(new.allProtocolDefinitions.values),
                containerKind: .protocol,
                identity: { ABIKey.makeUnwrappingType(for: $0.protocolName.node) },
                name: { $0.protocolName.name },
                members: { self.memberRecords(of: $0) }
            ),
            typeExtensions: diffExtensions(old.typeExtensionDefinitions, new.typeExtensionDefinitions, .typeExtension),
            protocolExtensions: diffExtensions(old.protocolExtensionDefinitions, new.protocolExtensionDefinitions, .protocolExtension),
            typeAliasExtensions: diffExtensions(old.typeAliasExtensionDefinitions, new.typeAliasExtensionDefinitions, .typeAliasExtension),
            conformanceExtensions: diffExtensions(old.conformanceExtensionDefinitions, new.conformanceExtensionDefinitions, .conformanceExtension),
            globalVariables: diffMembers(
                old: old.globalVariableDefinitions.map(MemberRecord.make),
                new: new.globalVariableDefinitions.map(MemberRecord.make)
            ),
            globalFunctions: diffMembers(
                old: old.globalFunctionDefinitions.map(MemberRecord.make),
                new: new.globalFunctionDefinitions.map(MemberRecord.make)
            )
        )
    }

    // MARK: - Container level

    /// The single container matcher every axis specializes: match `old`/`new`
    /// by `identity`, emit `.added`/`.removed` for the asymmetric sides, and
    /// for matched pairs diff their members — reporting `.modified` only when a
    /// member actually changed.
    private func diffContainers<Container>(
        old: [Container],
        new: [Container],
        containerKind: ContainerKind,
        identity: (Container) -> ABIKey,
        name: (Container) -> String,
        members: (Container) -> [MemberRecord]
    ) -> [ContainerChange] {
        let matched = threeWayMatch(old: old, new: new, identity: identity)

        var changes: [ContainerChange] = []
        changes.append(contentsOf: matched.removed.map {
            ContainerChange(key: identity($0), name: name($0), containerKind: containerKind, status: .removed, memberChanges: [])
        })
        changes.append(contentsOf: matched.added.map {
            ContainerChange(key: identity($0), name: name($0), containerKind: containerKind, status: .added, memberChanges: [])
        })
        for (oldContainer, newContainer) in matched.common {
            let memberChanges = diffMembers(old: members(oldContainer), new: members(newContainer))
            if !memberChanges.isEmpty {
                changes.append(ContainerChange(
                    key: identity(newContainer),
                    name: name(newContainer),
                    containerKind: containerKind,
                    status: .modified,
                    memberChanges: memberChanges
                ))
            }
        }
        return sorted(changes, key: \.key, status: \.status)
    }

    /// Diff one indexer extension bucket. The bucket maps an `ExtensionName`
    /// (target + kind) to *many* `ExtensionDefinition`s — the indexer splits a
    /// type's conformances, conditional blocks, and synthetic nested-type
    /// blocks into separate definitions all filed under the same name.
    ///
    /// We diff per `ExtensionName` and **merge the member records across every
    /// `ExtensionDefinition` in the bucket**, because the extension boundary
    /// itself is not exported — only the members (and the witness members of
    /// conformances) are. Merging is what makes adding/removing a whole
    /// conformance visible (its witness members join/leave the merged set), and
    /// it avoids the silent-drop collisions that per-definition keying suffered
    /// when two definitions on one target shared an identity (multiple
    /// conformances key the same; a member block and a synthetic nested-type
    /// block key the same).
    ///
    /// TODO(P2): per-conformance / per-`where`-block attribution (which
    /// conformance or constraint block a member belongs to) — needs the indexer
    /// to plumb the resolved protocol name onto each `ExtensionDefinition`.
    private func diffExtensions(
        _ old: OrderedDictionary<ExtensionName, [ExtensionDefinition]>,
        _ new: OrderedDictionary<ExtensionName, [ExtensionDefinition]>,
        _ containerKind: ContainerKind
    ) -> [ContainerChange] {
        func buckets(_ dictionary: OrderedDictionary<ExtensionName, [ExtensionDefinition]>) -> [ExtensionBucket] {
            dictionary.map { ExtensionBucket(name: $0.key, definitions: $0.value) }
        }
        return diffContainers(
            old: buckets(old),
            new: buckets(new),
            containerKind: containerKind,
            identity: { self.extensionBucketKey($0.name) },
            name: { $0.name.name },
            members: { bucket in bucket.definitions.flatMap { self.memberRecords(of: $0) } }
        )
    }

    private struct ExtensionBucket {
        let name: ExtensionName
        let definitions: [ExtensionDefinition]
    }

    /// Identity for an extension bucket: the target node plus an explicit kind
    /// token, so `extension`s on a struct vs a class of the same name (or the
    /// four extension kinds) stay distinct.
    private func extensionBucketKey(_ name: ExtensionName) -> ABIKey {
        .printed("extbucket:\(Self.extensionKindToken(name.kind))|\(ABIKey.makeUnwrappingType(for: name.node).sortKey)")
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
        let oldByKey = keyed(old, by: identity)
        let newByKey = keyed(new, by: identity)

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

    /// Index a sequence by a derived key.
    ///
    /// Known limitation: on a key collision this keeps the first element and
    /// drops the rest. With the kind-prefixed, bound-generic-preserving
    /// `ABIKey` fallback a collision between two genuinely-distinct
    /// declarations is not expected — legitimate overloads have distinct
    /// mangled keys, fields / cases / associated types are name-namespaced, and
    /// extensions are diffed per `ExtensionName` bucket (members merged) so the
    /// multiple definitions the indexer files under one name can't collide here
    /// — but if one ever occurs the dropped element is currently silent.
    /// TODO(P2): surface colliding keys on the result instead of dropping.
    private func keyed<Element>(_ elements: [Element], by key: (Element) -> ABIKey) -> [ABIKey: Element] {
        var result: [ABIKey: Element] = [:]
        result.reserveCapacity(elements.count)
        for element in elements {
            let elementKey = key(element)
            if result[elementKey] == nil {
                result[elementKey] = element
            }
        }
        return result
    }

    /// Deterministic ordering by key string then status, so repeated runs over
    /// the same inputs produce identical output.
    private func sorted<Change>(_ changes: [Change], key: (Change) -> ABIKey, status: (Change) -> ChangeStatus) -> [Change] {
        changes.sorted { lhs, rhs in
            (key(lhs).sortKey, status(lhs).sortRank) < (key(rhs).sortKey, status(rhs).sortRank)
        }
    }
}
