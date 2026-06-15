@_spi(Support) @testable import SwiftDeclaration
import SwiftDiffing
import Testing
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
