@_spi(Support) @testable import SwiftDeclaration
@testable import SwiftDiffing
import Testing
import Foundation
import Demangling
import OrderedCollections
@_spi(Internals) import MachOSymbols

// MARK: - Per-conformance / per-where-block attribution
//
// Extension containers are keyed per (target, protocol, where clause,
// retroactive). These tests drive the freeze path with Mach-O-free
// `ExtensionDefinition`s (the package initializer) so splitting, keying, and
// the downstream diff semantics are validated without a binary.

@Suite("Extension container attribution")
struct ABIExtensionAttributionTests {
    // MARK: Fixtures

    private func targetNode(_ name: String) -> Node {
        Node.create(kind: .type, child: Node.create(kind: .structure, children: [
            Node.create(kind: .module, text: "M"),
            Node.create(kind: .identifier, text: name),
        ]))
    }

    private func protocolName(_ name: String) -> ProtocolName {
        ProtocolName(node: Node.create(kind: .type, child: Node.create(kind: .protocol, children: [
            Node.create(kind: .module, text: "M"),
            Node.create(kind: .identifier, text: name),
        ])))
    }

    private func extensionName(_ target: String) -> ExtensionName {
        ExtensionName(node: targetNode(target), kind: .type(.struct))
    }

    private func whereClause(_ text: String) -> Node {
        Node.create(kind: .identifier, text: text)
    }

    private func function(_ name: String) -> FunctionDefinition {
        let node = Node.create(kind: .function, children: [
            Node.create(kind: .structure),
            Node.create(kind: .identifier, text: name),
            Node.create(kind: .type),
        ])
        return FunctionDefinition(
            node: node,
            name: name,
            kind: .function,
            symbol: DemangledSymbol(symbol: Symbol(offset: 0, name: "$s_\(name)"), demangledNode: makeNodeReference(node)),
            isGlobalOrStatic: false,
            methodDescriptor: nil,
            offset: nil,
            vtableOffset: nil
        )
    }

    private func conformance(
        _ target: String,
        to protocolText: String,
        where whereText: String? = nil,
        witnesses: [AssociatedTypeWitnessProjection] = []
    ) -> (name: ExtensionName, definition: ExtensionDefinition) {
        let name = extensionName(target)
        let definition = ExtensionDefinition(
            extensionName: name,
            genericSignature: whereText.map { whereClause($0) },
            conformingProtocolName: protocolName(protocolText),
            resolvedAssociatedTypeWitnesses: witnesses
        )
        return (name, definition)
    }

    private func snapshot(_ entries: [(name: ExtensionName, definition: ExtensionDefinition)]) -> ABISnapshot {
        var buckets: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]
        for entry in entries {
            buckets[entry.name, default: []].append(entry.definition)
        }
        return ABIDiffer().snapshot(of: ABIModule(conformanceExtensionDefinitions: buckets))
    }

    // MARK: Key composition (pure seam)

    @Test("the container key folds in kind, target, protocol, where, and retroactive")
    func keyComposition() {
        let base = ABIDiffer.extensionContainerKey(kindToken: "struct", targetSortKey: "T", protocolSortKey: "P", whereSortKey: "W", isRetroactive: false)
        #expect(base == .printed("extbucket:struct|T|proto:P|where:W|retro:0"))
        #expect(base != ABIDiffer.extensionContainerKey(kindToken: "struct", targetSortKey: "T", protocolSortKey: "Q", whereSortKey: "W", isRetroactive: false))
        #expect(base != ABIDiffer.extensionContainerKey(kindToken: "struct", targetSortKey: "T", protocolSortKey: "P", whereSortKey: "V", isRetroactive: false))
        #expect(base != ABIDiffer.extensionContainerKey(kindToken: "struct", targetSortKey: "T", protocolSortKey: "P", whereSortKey: "W", isRetroactive: true))
        let bare = ABIDiffer.extensionContainerKey(kindToken: "struct", targetSortKey: "T", protocolSortKey: nil, whereSortKey: nil, isRetroactive: false)
        #expect(bare == .printed("extbucket:struct|T|proto:-|where:-|retro:0"))
    }

    // MARK: Freeze-level splitting

    @Test("two conformances of one target freeze into two containers with attribution")
    func splitsPerConformance() {
        let frozen = snapshot([
            conformance("Foo", to: "P"),
            conformance("Foo", to: "Q"),
        ])
        #expect(frozen.conformanceExtensions.count == 2)
        #expect(frozen.conformanceExtensions.map(\.name).sorted() == ["M.Foo: M.P", "M.Foo: M.Q"])
        #expect(frozen.conformanceExtensions.compactMap(\.conformedProtocolName).sorted() == ["M.P", "M.Q"])
    }

    @Test("conditional blocks split per where clause and no longer collide")
    func splitsPerWhereBlock() {
        // The historical collision shape: two conditional extensions each
        // declaring the same-identity member.
        let blockP = conformance("Foo", to: "P", where: "whereP")
        blockP.definition.functions.append(function("m"))
        let blockQ = conformance("Foo", to: "P", where: "whereQ")
        blockQ.definition.functions.append(function("m"))

        let frozen = snapshot([blockP, blockQ])
        #expect(frozen.conformanceExtensions.count == 2)
        #expect(frozen.conformanceExtensions.allSatisfy { $0.members.count == 1 })
        // Each block is its own keying scope — the realistic collision source
        // is structurally gone.
        #expect(frozen.keyCollisions().isEmpty)
        #expect(ABIDiffer().diff(old: frozen, new: frozen).isEmpty)
    }

    // MARK: Diff semantics

    @Test("adding a conformance is a container-level .added with the protocol in the name")
    func addedConformanceIsContainerLevel() {
        let old = snapshot([conformance("Foo", to: "P")])
        let new = snapshot([conformance("Foo", to: "P"), conformance("Foo", to: "Q")])
        let diff = ABIDiffer().diff(old: old, new: new)
        #expect(diff.conformanceExtensions.count == 1)
        #expect(diff.conformanceExtensions.first?.status == .added)
        #expect(diff.conformanceExtensions.first?.name == "M.Foo: M.Q")
        #expect(diff.isBackwardCompatible)
    }

    @Test("a where-clause change flips the container identity: removed + added")
    func whereClauseChangeIsRemovedPlusAdded() {
        let old = snapshot([conformance("Foo", to: "P", where: "T: Equatable")])
        let new = snapshot([conformance("Foo", to: "P", where: "T: Hashable")])
        let diff = ABIDiffer().diff(old: old, new: new)
        #expect(diff.conformanceExtensions.map(\.status).sorted { $0.sortRank < $1.sortRank } == [.removed, .added])
        #expect(diff.hasBreakingChange)
    }

    @Test("a retroactive toggle flips the container identity")
    func retroactiveToggleIsRemovedPlusAdded() {
        let plain = conformance("Foo", to: "P")
        let retroactive = conformance("Foo", to: "P")
        retroactive.definition.isRetroactive = true
        let diff = ABIDiffer().diff(old: snapshot([plain]), new: snapshot([retroactive]))
        #expect(diff.conformanceExtensions.map(\.status).sorted { $0.sortRank < $1.sortRank } == [.removed, .added])
        #expect(diff.conformanceExtensions.first { $0.status == .added }?.name == "M.Foo: M.P (retroactive)")
    }

    // MARK: Associated-type witnesses

    @Test("re-binding an associated-type witness reports .modified")
    func witnessRebindIsModified() {
        let old = snapshot([conformance("Foo", to: "P", witnesses: [.init(name: "Element", substitutedTypeText: "Swift.Int")])])
        let new = snapshot([conformance("Foo", to: "P", witnesses: [.init(name: "Element", substitutedTypeText: "Swift.String")])])
        let diff = ABIDiffer().diff(old: old, new: new)
        let change = diff.conformanceExtensions.first?.memberChanges.first
        #expect(change?.status == .modified)
        #expect(change?.kind == .associatedTypeWitness)
        #expect(change?.oldSignature == "typealias Element = Swift.Int")
        #expect(change?.newSignature == "typealias Element = Swift.String")
    }

    @Test("witness projections merge without duplicates when typealias-only blocks are absorbed")
    func absorbDeduplicatesWitnesses() {
        let primary = conformance("Foo", to: "P", witnesses: [.init(name: "Element", substitutedTypeText: "Swift.Int")])
        let secondary = conformance("Foo", to: "P", witnesses: [
            .init(name: "Element", substitutedTypeText: "Swift.Int"),
            .init(name: "Index", substitutedTypeText: "Swift.Int"),
        ])
        primary.definition.absorbAssociatedTypes(of: secondary.definition)
        #expect(primary.definition.resolvedAssociatedTypeWitnesses.map(\.name) == ["Element", "Index"])
    }
}

private func makeNodeReference(_ node: Node) -> NodeReference {
    var nodeStoreBuilder = NodeStoreBuilder()
    let nodeIndex = nodeStoreBuilder.intern(node)
    return nodeStoreBuilder.freeze().reference(at: nodeIndex)
}
