import Demangling
import SwiftDeclaration

/// Diffs the Swift ABI of two indexed modules by keying every declaration on
/// its remangled `Node` and computing a recursive three-way set difference.
///
/// Synchronous and Mach-O-free: it operates purely on the (already-indexed)
/// `SwiftDeclaration` model. Build the two `ABIModule` inputs from two prepared
/// indexers, then call ``diff(old:new:)``. Output arrays are sorted
/// deterministically so the result is reproducible for snapshot/baseline use.
public struct ABIDiffer: Sendable {
    public init() {}

    // MARK: - Top level

    public func diff(old: ABIModule, new: ABIModule) -> ABIDiff {
        ABIDiff(types: diffTypes(old: old.types, new: new.types))
        // TODO(P2): protocols, extensions, globals — each a thin specialization
        // of `threeWayMatch` below.
    }

    private func diffTypes(old: [TypeDefinition], new: [TypeDefinition]) -> [TypeChange] {
        let matched = threeWayMatch(old: old, new: new) { ABIKey.makeUnwrappingType(for: $0.typeName.node) }

        var changes: [TypeChange] = []
        changes.append(contentsOf: matched.removed.map { typeChange($0, status: .removed, memberChanges: []) })
        changes.append(contentsOf: matched.added.map { typeChange($0, status: .added, memberChanges: []) })
        for (oldDefinition, newDefinition) in matched.common {
            let memberChanges = diffMembers(
                old: memberRecords(of: oldDefinition),
                new: memberRecords(of: newDefinition)
            )
            if !memberChanges.isEmpty {
                changes.append(typeChange(newDefinition, status: .modified, memberChanges: memberChanges))
            }
        }
        return sorted(changes, key: \.key, status: \.status)
    }

    private func typeChange(_ definition: TypeDefinition, status: ChangeStatus, memberChanges: [MemberChange]) -> TypeChange {
        TypeChange(
            key: ABIKey.makeUnwrappingType(for: definition.typeName.node),
            name: definition.typeName.name,
            status: status,
            memberChanges: memberChanges
        )
    }

    // MARK: - Member level (test seam)

    /// Three-way set difference over member records, keyed by `identityKey`.
    /// Public so it can be unit-tested without constructing a `TypeDefinition`
    /// (whose initializer needs a Mach-O).
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

    /// Projects every ABI-relevant member of a type into diff records. Iterates
    /// the typed collections (not `orderedMembers`) so static-ness stays in
    /// scope and `fields` / `constructors` — which `orderedMembers` omits — are
    /// covered. Enum cases carry their tag (declaration order); struct/class
    /// stored fields do not (resilient reordering is binary-compatible).
    func memberRecords(of definition: TypeDefinition) -> [MemberRecord] {
        var records: [MemberRecord] = []
        if case .enum = definition.type {
            for (tag, field) in definition.fields.enumerated() {
                records.append(.makeCase(field, tag: tag))
            }
        } else {
            records.append(contentsOf: definition.fields.map(MemberRecord.make))
        }
        records.append(contentsOf: definition.variables.map(MemberRecord.make))
        records.append(contentsOf: definition.staticVariables.map(MemberRecord.make))
        records.append(contentsOf: definition.functions.map(MemberRecord.make))
        records.append(contentsOf: definition.staticFunctions.map(MemberRecord.make))
        records.append(contentsOf: definition.subscripts.map(MemberRecord.make))
        records.append(contentsOf: definition.staticSubscripts.map(MemberRecord.make))
        records.append(contentsOf: definition.allocators.map(MemberRecord.make))
        records.append(contentsOf: definition.constructors.map(MemberRecord.make))
        if definition.hasDeallocator {
            records.append(.makeDeinit())
        }
        return records
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
    /// mangled keys, and fields / cases are name-namespaced — but if one ever
    /// occurs the dropped element is currently silent.
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
