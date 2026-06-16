@_spi(Support) @testable import SwiftDeclaration
@testable import SwiftDiffing
import Testing
import Foundation
import Demangling
@_spi(Internals) import MachOSymbols

// MARK: - Core three-way set-diff algorithm
//
// These drive `diffMembers` with explicitly-keyed `MemberRecord`s so the
// algorithm is validated deterministically, independent of remangle fidelity.

@Suite("ABIDiffer.diffMembers")
struct ABIDifferAlgorithmTests {
    private func record(_ identity: String, payload: String? = nil, kind: MemberKind = .function) -> MemberRecord {
        MemberRecord(
            identityKey: .mangled(identity),
            payloadKey: .mangled(payload ?? identity),
            kind: kind,
            signature: identity
        )
    }

    @Test("a member only on the new side is .added")
    func added() {
        let changes = ABIDiffer().diffMembers(old: [record("foo")], new: [record("foo"), record("bar")])
        #expect(changes.count == 1)
        #expect(changes.first?.status == .added)
        #expect(changes.first?.key == .mangled("bar"))
        #expect(changes.first?.oldSignature == nil)
        #expect(changes.first?.newSignature == "bar")
    }

    @Test("a member only on the old side is .removed")
    func removed() {
        let changes = ABIDiffer().diffMembers(old: [record("foo"), record("bar")], new: [record("foo")])
        #expect(changes.count == 1)
        #expect(changes.first?.status == .removed)
        #expect(changes.first?.key == .mangled("bar"))
        #expect(changes.first?.newSignature == nil)
    }

    @Test("matched identity with differing payload is .modified")
    func modified() {
        let old = [record("x", payload: "Int", kind: .field)]
        let new = [record("x", payload: "String", kind: .field)]
        let changes = ABIDiffer().diffMembers(old: old, new: new)
        #expect(changes.count == 1)
        #expect(changes.first?.status == .modified)
        #expect(changes.first?.kind == .field)
    }

    @Test("matched identity with identical payload yields no change")
    func unchanged() {
        let changes = ABIDiffer().diffMembers(old: [record("foo")], new: [record("foo")])
        #expect(changes.isEmpty)
    }

    @Test("an identity rename is add+remove, never a single .modified")
    func renameIsAddRemove() {
        let old = [record("x", payload: "Int", kind: .field)]
        let new = [record("y", payload: "Int", kind: .field)]
        let changes = ABIDiffer().diffMembers(old: old, new: new)
        #expect(changes.filter { $0.status == .added }.count == 1)
        #expect(changes.filter { $0.status == .removed }.count == 1)
        #expect(changes.contains { $0.status == .modified } == false)
    }

    @Test("empty vs empty is empty")
    func emptyVsEmpty() {
        #expect(ABIDiffer().diffMembers(old: [], new: []).isEmpty)
    }

    @Test("output is sorted deterministically by key")
    func outputIsSorted() {
        let new = [record("zeta"), record("alpha"), record("mike"), record("bravo")]
        let changes = ABIDiffer().diffMembers(old: [], new: new)
        let keys = changes.map(\.key.sortKey)
        #expect(keys == keys.sorted())
    }
}

// MARK: - Projection from the model + keying

@Suite("MemberRecord / ABIKey projection")
struct ABIDifferProjectionTests {
    private func functionNode(_ name: String) -> Node {
        Node.create(kind: .function, children: [
            Node.create(kind: .structure),
            Node.create(kind: .identifier, text: name),
            Node.create(kind: .type),
        ])
    }

    private func function(_ name: String, kind: FunctionKind = .function) -> FunctionDefinition {
        let node = functionNode(name)
        return FunctionDefinition(
            node: node,
            name: name,
            kind: kind,
            symbol: DemangledSymbol(symbol: Symbol(offset: 0, name: "$s_\(name)"), demangledNode: node),
            isGlobalOrStatic: false,
            methodDescriptor: nil,
            offset: nil,
            vtableOffset: nil
        )
    }

    private func nominalType(_ name: String) -> Node {
        Node.create(kind: .type, child: Node.create(kind: .structure, children: [
            Node.create(kind: .module, text: "Swift"),
            Node.create(kind: .identifier, text: name),
        ]))
    }

    private func field(_ name: String, type: String) -> FieldDefinition {
        FieldDefinition(name: name, typeNode: nominalType(type), flags: FieldFlags())
    }

    private func accessor(_ kind: AccessorKind, _ name: String) -> Accessor {
        let node = Node.create(kind: .identifier, text: name)
        return Accessor(
            kind: kind,
            symbol: DemangledSymbol(symbol: Symbol(offset: 0, name: "$s_acc_\(name)"), demangledNode: node),
            methodDescriptor: nil,
            offset: nil,
            vtableOffset: nil
        )
    }

    private func variable(_ name: String, accessors: [AccessorKind]) -> VariableDefinition {
        VariableDefinition(
            node: functionNode(name),
            name: name,
            accessors: accessors.map { accessor($0, name) },
            isGlobalOrStatic: false
        )
    }

    @Test("function kind maps onto MemberKind")
    func functionKindMapping() {
        #expect(MemberRecord.make(function("f", kind: .function)).kind == .function)
        #expect(MemberRecord.make(function("g", kind: .allocator)).kind == .allocator)
        #expect(MemberRecord.make(function("h", kind: .constructor)).kind == .constructor)
    }

    @Test("a field's identity lives in its own name namespace")
    func fieldIdentityNamespace() {
        let record = MemberRecord.make(field("count", type: "Int"))
        #expect(record.kind == .field)
        #expect(record.identityKey == .printed("field:count"))
    }

    @Test("same-named fields with different types diff as .modified")
    func fieldRetypeIsModified() {
        let old = [MemberRecord.make(field("count", type: "Int"))]
        let new = [MemberRecord.make(field("count", type: "String"))]
        let changes = ABIDiffer().diffMembers(old: old, new: new)
        #expect(changes.count == 1)
        #expect(changes.first?.status == .modified)
        #expect(changes.first?.kind == .field)
    }

    @Test("let -> var (gaining a setter) diffs as .modified, not silently nothing")
    func gainingSetterIsModified() {
        let readOnly = [MemberRecord.make(variable("value", accessors: [.getter]))]
        let readWrite = [MemberRecord.make(variable("value", accessors: [.getter, .setter]))]
        let changes = ABIDiffer().diffMembers(old: readOnly, new: readWrite)
        #expect(changes.count == 1)
        #expect(changes.first?.status == .modified)
        #expect(changes.first?.kind == .variable)
    }

    @Test("reordering enum cases renumbers tags, so the moved cases diff as .modified")
    func enumCaseReorderIsModified() {
        let old = [
            MemberRecord.makeCase(field("a", type: "Int"), tag: 0),
            MemberRecord.makeCase(field("b", type: "Int"), tag: 1),
        ]
        let new = [
            MemberRecord.makeCase(field("a", type: "Int"), tag: 1),
            MemberRecord.makeCase(field("b", type: "Int"), tag: 0),
        ]
        let changes = ABIDiffer().diffMembers(old: old, new: new)
        #expect(changes.count == 2)
        #expect(changes.allSatisfy { $0.status == .modified })
        #expect(changes.allSatisfy { $0.kind == .enumCase })
    }

    @Test("appending an enum case leaves existing tags intact (only the new case is .added)")
    func enumCaseAppendIsAdded() {
        let old = [MemberRecord.makeCase(field("a", type: "Int"), tag: 0)]
        let new = [
            MemberRecord.makeCase(field("a", type: "Int"), tag: 0),
            MemberRecord.makeCase(field("b", type: "Int"), tag: 1),
        ]
        let changes = ABIDiffer().diffMembers(old: old, new: new)
        #expect(changes.count == 1)
        #expect(changes.first?.status == .added)
        #expect(changes.first?.kind == .enumCase)
    }

    @Test("a deinit appearing on the new side diffs as .added")
    func deinitPresence() {
        let changes = ABIDiffer().diffMembers(old: [], new: [MemberRecord.makeDeinit()])
        #expect(changes.count == 1)
        #expect(changes.first?.status == .added)
        #expect(changes.first?.kind == .deinit)
    }

    @Test("ABIKey.make is stable across structurally-equal but distinct node instances")
    func keyDeterminism() {
        // Two separately-built trees with identical structure must key equal —
        // that cross-instance stability is what makes the diff work across two
        // independently-indexed binaries.
        #expect(ABIKey.make(for: functionNode("stable")) == ABIKey.make(for: functionNode("stable")))
    }
}

// MARK: - Full-classification projections (protocols / generalized members)

/// A minimal `Definition` so the generalized `sharedMemberRecords(of:)` can be
/// exercised without a Mach-O-backed `TypeDefinition`/`ProtocolDefinition`.
private final class StubDefinition: Definition {
    var isIndexed = true
    var orderedMembers: [OrderedMember] = []
    var allocators: [FunctionDefinition] = []
    var constructors: [FunctionDefinition] = []
    var variables: [VariableDefinition] = []
    var functions: [FunctionDefinition] = []
    var subscripts: [SubscriptDefinition] = []
    var staticVariables: [VariableDefinition] = []
    var staticFunctions: [FunctionDefinition] = []
    var staticSubscripts: [SubscriptDefinition] = []
}

@Suite("Classification: associated types & generalized member projection")
struct ABIDifferClassificationTests {
    private func functionNode(_ name: String) -> Node {
        Node.create(kind: .function, children: [
            Node.create(kind: .structure),
            Node.create(kind: .identifier, text: name),
            Node.create(kind: .type),
        ])
    }

    private func function(_ name: String) -> FunctionDefinition {
        let node = functionNode(name)
        return FunctionDefinition(
            node: node,
            name: name,
            kind: .function,
            symbol: DemangledSymbol(symbol: Symbol(offset: 0, name: "$s_\(name)"), demangledNode: node),
            isGlobalOrStatic: false,
            methodDescriptor: nil,
            offset: nil,
            vtableOffset: nil
        )
    }

    private func variable(_ name: String) -> VariableDefinition {
        VariableDefinition(node: functionNode(name), name: name, accessors: [], isGlobalOrStatic: false)
    }

    @Test("associated type: same name is unchanged, a rename is add+remove")
    func associatedTypeDiff() {
        let same = ABIDiffer().diffMembers(
            old: [MemberRecord.makeAssociatedType("Element")],
            new: [MemberRecord.makeAssociatedType("Element")]
        )
        #expect(same.isEmpty)

        let renamed = ABIDiffer().diffMembers(
            old: [MemberRecord.makeAssociatedType("Element")],
            new: [MemberRecord.makeAssociatedType("Item")]
        )
        #expect(renamed.filter { $0.status == .added }.count == 1)
        #expect(renamed.filter { $0.status == .removed }.count == 1)
        #expect(renamed.allSatisfy { $0.kind == .associatedType })
    }

    @Test("sharedMemberRecords projects every Definition collection it is given")
    func sharedMemberProjection() {
        let stub = StubDefinition()
        stub.variables = [variable("value")]
        stub.functions = [function("foo")]
        stub.staticFunctions = [function("bar")]
        let records = ABIDiffer().sharedMemberRecords(of: stub)
        #expect(records.count == 3)
        #expect(records.contains { $0.kind == .variable })
        #expect(records.filter { $0.kind == .function }.count == 2)
    }

    @Test("members of different kinds with the same spelling do not collide")
    func mixedKindNamespacing() {
        let field = MemberRecord(identityKey: .printed("field:x"), payloadKey: .printed("field:x"), kind: .field, signature: "x")
        let changes = ABIDiffer().diffMembers(old: [], new: [field, MemberRecord.makeAssociatedType("x")])
        #expect(changes.count == 2)
        #expect(changes.contains { $0.kind == .field })
        #expect(changes.contains { $0.kind == .associatedType })
    }

    @Test("extension kind tokens are injective (explicit, not reflection)")
    func extensionKindTokensAreInjective() {
        let tokens = [
            ABIDiffer.extensionKindToken(.type(.struct)),
            ABIDiffer.extensionKindToken(.type(.class)),
            ABIDiffer.extensionKindToken(.type(.enum)),
            ABIDiffer.extensionKindToken(.protocol),
            ABIDiffer.extensionKindToken(.typeAlias),
        ]
        #expect(Set(tokens).count == tokens.count)
    }

    @Test("accessor kind tokens are injective (explicit, not reflection)")
    func accessorKindTokensAreInjective() {
        let tokens = [
            MemberRecord.accessorKindToken(.getter),
            MemberRecord.accessorKindToken(.setter),
            MemberRecord.accessorKindToken(.modifyAccessor),
            MemberRecord.accessorKindToken(.readAccessor),
            MemberRecord.accessorKindToken(.none),
        ]
        #expect(Set(tokens).count == tokens.count)
    }
}

// MARK: - Codable persistence of the diff result

@Suite("ABIDiff Codable")
struct ABIDiffCodableTests {
    @Test("a populated ABIDiff survives a JSON encode/decode round-trip")
    func roundTrip() throws {
        let diff = ABIDiff(
            types: [
                ContainerChange(
                    key: .mangled("$s1M3FooV"),
                    name: "M.Foo",
                    containerKind: .type,
                    status: .modified,
                    memberChanges: [
                        MemberChange(key: .printed("field:count"), kind: .field, status: .added, oldSignature: nil, newSignature: "count: Int"),
                    ]
                ),
            ],
            conformanceExtensions: [
                ContainerChange(key: .printed("extbucket:struct|0:$s1M3FooV"), name: "M.Foo", containerKind: .conformanceExtension, status: .added, memberChanges: []),
            ],
            globalFunctions: [
                MemberChange(key: .mangled("$s1M3baryyF"), kind: .function, status: .removed, oldSignature: "bar()", newSignature: nil),
            ]
        )
        let data = try JSONEncoder().encode(diff)
        let decoded = try JSONDecoder().decode(ABIDiff.self, from: data)
        #expect(decoded == diff)
    }

    @Test("an empty ABIDiff round-trips and stays empty")
    func emptyRoundTrip() throws {
        let data = try JSONEncoder().encode(ABIDiff())
        let decoded = try JSONDecoder().decode(ABIDiff.self, from: data)
        #expect(decoded.isEmpty)
    }
}

// MARK: - Snapshot diff (container-level, finally testable without Mach-O)

@Suite("ABISnapshot diff & persistence")
struct ABISnapshotTests {
    private func member(_ identity: String, payload: String? = nil, kind: MemberKind = .function) -> MemberRecord {
        MemberRecord(identityKey: .mangled(identity), payloadKey: .mangled(payload ?? identity), kind: kind, signature: identity)
    }

    private func container(_ key: String, kind: ContainerKind = .type, members: [MemberRecord] = []) -> ContainerSnapshot {
        ContainerSnapshot(key: .mangled(key), name: key, kind: kind, members: members)
    }

    @Test("a container only on the new side diffs as .added")
    func addedContainer() {
        let old = ABISnapshot(types: [container("A")])
        let new = ABISnapshot(types: [container("A"), container("B")])
        let diff = ABIDiffer().diff(old: old, new: new)
        #expect(diff.types.count == 1)
        #expect(diff.types.first?.status == .added)
        #expect(diff.types.first?.key == .mangled("B"))
    }

    @Test("a container only on the old side diffs as .removed")
    func removedContainer() {
        let old = ABISnapshot(protocols: [container("P", kind: .protocol), container("Q", kind: .protocol)])
        let new = ABISnapshot(protocols: [container("P", kind: .protocol)])
        let diff = ABIDiffer().diff(old: old, new: new)
        #expect(diff.protocols.count == 1)
        #expect(diff.protocols.first?.status == .removed)
    }

    @Test("a member change inside a surviving container diffs as .modified")
    func modifiedContainer() {
        let old = ABISnapshot(types: [container("A", members: [member("a.foo")])])
        let new = ABISnapshot(types: [container("A", members: [member("a.foo"), member("a.bar")])])
        let diff = ABIDiffer().diff(old: old, new: new)
        #expect(diff.types.count == 1)
        #expect(diff.types.first?.status == .modified)
        #expect(diff.types.first?.memberChanges.count == 1)
        #expect(diff.types.first?.memberChanges.first?.status == .added)
    }

    @Test("a container with no member change is absent from the diff")
    func unchangedContainer() {
        let snapshot = ABISnapshot(types: [container("A", members: [member("a.foo")])])
        #expect(ABIDiffer().diff(old: snapshot, new: snapshot).isEmpty)
    }

    @Test("a populated ABISnapshot survives a JSON encode/decode round-trip")
    func snapshotRoundTrip() throws {
        let snapshot = ABISnapshot(
            types: [container("A", members: [member("a.foo", kind: .function)])],
            conformanceExtensions: [container("extbucket:struct|0:$s1A", kind: .conformanceExtension)],
            globalFunctions: [member("g.bar")]
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ABISnapshot.self, from: data)
        #expect(decoded == snapshot)
    }
}

// MARK: - Textual report

@Suite("ABIDiffReporter")
struct ABIDiffReporterTests {
    @Test("an empty diff reports no changes")
    func empty() {
        #expect(ABIDiffReporter().report(ABIDiff()) == "No ABI changes.")
    }

    @Test("renders added / removed / modified with +/-/~ sigils and member detail")
    func sigils() {
        let diff = ABIDiff(
            types: [
                ContainerChange(key: .mangled("A"), name: "M.Added", containerKind: .type, status: .added, memberChanges: []),
                ContainerChange(key: .mangled("B"), name: "M.Gone", containerKind: .type, status: .removed, memberChanges: []),
                ContainerChange(key: .mangled("C"), name: "M.Changed", containerKind: .type, status: .modified, memberChanges: [
                    MemberChange(key: .printed("field:count"), kind: .field, status: .added, oldSignature: nil, newSignature: "count: Int"),
                    MemberChange(key: .mangled("old"), kind: .function, status: .removed, oldSignature: "bar()", newSignature: nil),
                ]),
            ],
            globalFunctions: [
                MemberChange(key: .mangled("g"), kind: .function, status: .modified, oldSignature: "f() -> Int", newSignature: "f() -> String"),
            ]
        )
        let report = ABIDiffReporter().report(diff)
        #expect(report.contains("+ M.Added"))
        #expect(report.contains("- M.Gone"))
        #expect(report.contains("~ M.Changed"))
        #expect(report.contains("+ count: Int"))
        #expect(report.contains("- bar()"))
        #expect(report.contains("f() -> Int → f() -> String"))
        #expect(report.contains("Global functions:"))
    }
}

// MARK: - Compatibility classification

@Suite("Compatibility")
struct CompatibilityTests {
    @Test("an added container is additive; a removed one is breaking")
    func containerAddRemove() {
        let added = ContainerChange(key: .mangled("A"), name: "A", containerKind: .type, status: .added, memberChanges: [])
        let removed = ContainerChange(key: .mangled("B"), name: "B", containerKind: .type, status: .removed, memberChanges: [])
        #expect(added.compatibility == .additive)
        #expect(removed.compatibility == .breaking)
    }

    @Test("a modified container is additive iff all its member changes are additive")
    func modifiedContainerClassification() {
        let onlyAdded = ContainerChange(key: .mangled("A"), name: "A", containerKind: .type, status: .modified, memberChanges: [
            MemberChange(key: .mangled("m"), kind: .function, status: .added, oldSignature: nil, newSignature: "m()"),
        ])
        let hasRemoval = ContainerChange(key: .mangled("B"), name: "B", containerKind: .type, status: .modified, memberChanges: [
            MemberChange(key: .mangled("m"), kind: .function, status: .added, oldSignature: nil, newSignature: "m()"),
            MemberChange(key: .mangled("g"), kind: .function, status: .removed, oldSignature: "g()", newSignature: nil),
        ])
        #expect(onlyAdded.compatibility == .additive)
        #expect(hasRemoval.compatibility == .breaking)
    }

    @Test("a diff with only additions is backward-compatible; a removal breaks it")
    func diffLevelClassification() {
        let additive = ABIDiff(types: [
            ContainerChange(key: .mangled("A"), name: "A", containerKind: .type, status: .added, memberChanges: []),
        ])
        #expect(additive.isBackwardCompatible)
        #expect(!additive.hasBreakingChange)

        let breaking = ABIDiff(globalFunctions: [
            MemberChange(key: .mangled("g"), kind: .function, status: .removed, oldSignature: "g()", newSignature: nil),
        ])
        #expect(breaking.hasBreakingChange)
        #expect(!breaking.isBackwardCompatible)
        #expect(breaking.breakingGlobalChanges.count == 1)
    }

    @Test("an empty diff is trivially backward-compatible")
    func emptyIsCompatible() {
        #expect(ABIDiff().isBackwardCompatible)
        #expect(!ABIDiff().hasBreakingChange)
    }
}
