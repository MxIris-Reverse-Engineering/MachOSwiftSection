import Foundation
import SwiftDeclaration
@_spi(Support) import SwiftIndexing
@_spi(Support) import SwiftPrinting
import SwiftDiffing
import SwiftDeclarationRendering
import MachOSwiftSection
import Semantic
import Demangling
import OrderedCollections

/// One matched declaration across the version axis: its `ABIKey` plus the
/// per-version elements, index-aligned with the axis (`nil` = absent on that
/// version). For the two-sided diff the axis is `[old, new]`.
struct UnionMatch<Element> {
    let key: ABIKey
    let elements: [Element?]
}

/// Where a matched member sits, for strategies that key facts per scope (the
/// evolution strategy's annotation lookup). The diff strategy ignores it.
enum UnionMemberScope {
    case global
    case container(ABIKey)
}

/// One member projected for union rendering: its identity/payload keys (the
/// same `MemberRecord` projections `ABIDiffer` freezes into snapshots, which
/// is what joins a member to its diff verdict or lineage) plus a closure that
/// renders just that member to a standalone `SemanticString` through its own
/// version's printer.
///
/// The walker builds every member's render closure at printer level 0 ON
/// PURPOSE: the member printers bake the accessor block's interior indentation
/// ABSOLUTELY from `level` ((level+1)*4 for accessors, level*4 for the closing
/// brace), while both format layers indent EVERY line of a unit by the unit's
/// own indent level — rendering at a real level would indent the interior
/// twice (the accessor-block double-indentation defect, fixed on the evolution
/// path first and unified here; pinned by `DiffMemberIndentationTests`).
/// Functions and fields ignore the parameter.
struct UnionRenderableMember {
    let identityKey: ABIKey
    /// Change detection (`MemberRecord.payloadKey`), read by the diff strategy
    /// only — the evolution strategy's change facts come from `ABIEvolution`.
    let payloadKey: ABIKey
    let render: () async -> SemanticString
}

/// One (target, protocol, where clause, retroactive) sub-group of an
/// `ExtensionName` bucket — the container granularity both union strategies
/// and `ABIDiffer.extensionContainerSnapshots` share.
struct ExtensionUnionContainer {
    let key: ABIKey
    let name: ExtensionName
    var definitions: [ExtensionDefinition]
}

/// How one union walk becomes concrete output lines.
///
/// The walker owns the STRUCTURE — matching and union ordering, extension
/// container splitting, member construction, category scheduling, body
/// composition — and the strategy owns the PRESENTATION: how a matched member
/// is emitted (`+`/`-` markers vs a lifecycle annotation), how a container
/// header resolves (both-sides pairing vs latest-renderable), and how a
/// container assembles. Genuinely divergent semantics (the diff path's
/// `HeaderOutcome` pairing, the evolution path's annotation anchoring) live in
/// the strategies, never in the walker.
protocol InterfaceUnionEmitting: Sendable {
    associatedtype Line: Sendable
    /// Whatever the strategy carries from header resolution to container
    /// assembly (the diff strategy carries both sides' headers plus the
    /// container marker; the evolution strategy carries one header).
    associatedtype ContainerHeader

    /// Resolve a type's header from its matched per-version elements, or
    /// `nil` to drop the whole declaration — members and braces under no
    /// header line are not valid Swift, and every failure must already be
    /// dispatched as an event before `nil` comes back.
    func resolveTypeHeader(elements: [TypeDefinition?], level: Int) async -> ContainerHeader?
    func resolveProtocolHeader(elements: [ProtocolDefinition?], level: Int) async -> ContainerHeader?

    /// Wrap an extension container's pre-built header text (extension headers
    /// are constructed from the container's representative and cannot fail).
    func resolveExtensionHeader(header: SemanticString, elements: [ExtensionUnionContainer?]) -> ContainerHeader

    /// Emit one matched member as zero or more units (a unit = one member
    /// side's lines; empty units are discarded by the walker). The diff
    /// strategy emits a modified member as two units (old `-`, new `+`); the
    /// evolution strategy emits at most one.
    func memberUnits(match: UnionMatch<UnionRenderableMember>, scope: UnionMemberScope, level: Int) async -> [[Line]]

    /// Assemble a container declaration into one flat line list from its
    /// resolved header and already-emitted body units.
    func assembleContainer(header: ContainerHeader, key: ABIKey, bodyUnits: [[Line]], level: Int) -> [Line]
}

/// The shared structure walk behind ``SwiftDiffableInterfaceRenderer`` (the
/// two-sided diff strategy) and ``SwiftEvolutionInterfaceRenderer`` (the N-way
/// annotation strategy): N versions in, block-grouped lines out.
///
/// Union ordering: the newest version's declaration order is the spine, and
/// declarations absent from the newest version are appended in the order of
/// the most recent version that still had them (scanning newest → oldest) —
/// for the two-sided axis this reduces exactly to "new order first, old-only
/// appended in old order". Keys are first-wins per version, mirroring
/// `ABIDiffer.keyed`. Member categories walk `MemberCategory.allCases` so the
/// category schedule stays identical to the printer's and a category can never
/// be silently dropped.
struct InterfaceUnionWalker<Strategy: InterfaceUnionEmitting> {
    /// Oldest → newest (for the diff strategy: `[old, new]`).
    let versions: [any InterfaceVersionRendering]
    let strategy: Strategy

    // MARK: - Top level

    /// The full classified stream: the outer array is the top-level
    /// declaration blocks in render order (globals → types → protocols → the
    /// four extension buckets), each inner array one block's lines. Empty
    /// blocks are dropped. Each global member is its own top-level block (no
    /// enclosing container), so the format separates them the same way it
    /// separates declarations.
    func blocks() async -> [[Strategy.Line]] {
        var blocks: [[Strategy.Line]] = []

        blocks += await memberListUnits(
            perVersion: versions.enumerated().map { versionIndex, version in
                version.globalVariableDefinitions.map { variableMember($0, versionIndex: versionIndex) }
            },
            scope: .global,
            level: 0
        )
        blocks += await memberListUnits(
            perVersion: versions.enumerated().map { versionIndex, version in
                version.globalFunctionDefinitions.map { functionMember($0, versionIndex: versionIndex) }
            },
            scope: .global,
            level: 0
        )
        blocks += await typeListUnits(perVersion: versions.map(\.rootTypeDefinitions), level: 1)
        blocks += await protocolListUnits(perVersion: versions.map(\.rootProtocolDefinitions), level: 1)
        blocks += await extensionBucketUnits(perVersion: versions.map(\.typeExtensionDefinitions))
        blocks += await extensionBucketUnits(perVersion: versions.map(\.protocolExtensionDefinitions))
        blocks += await extensionBucketUnits(perVersion: versions.map(\.typeAliasExtensionDefinitions))
        blocks += await extensionBucketUnits(perVersion: versions.map(\.conformanceExtensionDefinitions))

        return blocks.filter { !$0.isEmpty }
    }

    // MARK: - Types

    private func typeListUnits(perVersion: [[TypeDefinition]], level: Int) async -> [[Strategy.Line]] {
        var units: [[Strategy.Line]] = []
        for match in matchAcrossVersions(perVersion, key: { ABIKey.makeUnwrappingType(for: $0.typeName.node) }) {
            // Header first: when no version can render one, the body is never
            // computed and the declaration drops whole.
            guard let header = await strategy.resolveTypeHeader(elements: match.elements, level: level) else { continue }
            let bodyUnits = await typeBodyUnits(elements: match.elements, containerKey: match.key, level: level)
            let lines = strategy.assembleContainer(header: header, key: match.key, bodyUnits: bodyUnits, level: level)
            if !lines.isEmpty { units.append(lines) }
        }
        return units
    }

    /// The body of a type, mirroring `printTypeDefinition`'s composition
    /// order: nested types, nested protocols, stored fields / enum cases, the
    /// symbol-backed member categories, then `deinit`. A `nil` version
    /// contributes an empty list, so this one path serves declarations that
    /// exist on any subset of the axis.
    private func typeBodyUnits(elements: [TypeDefinition?], containerKey: ABIKey, level: Int) async -> [[Strategy.Line]] {
        var units: [[Strategy.Line]] = []

        units += await typeListUnits(perVersion: elements.map { $0?.typeChildren ?? [] }, level: level + 1)
        units += await protocolListUnits(perVersion: elements.map { $0?.protocolChildren ?? [] }, level: level + 1)

        units += await memberListUnits(perVersion: fieldMembers(elements: elements), scope: .container(containerKey), level: level)

        for category in MemberCategory.allCases {
            units += await memberListUnits(
                perVersion: elements.enumerated().map { versionIndex, definition in
                    renderableMembers(definition, in: category, versionIndex: versionIndex)
                },
                scope: .container(containerKey),
                level: level
            )
        }

        units += await memberListUnits(perVersion: deinitMembers(elements: elements), scope: .container(containerKey), level: level)

        return units
    }

    // MARK: - Protocols

    private func protocolListUnits(perVersion: [[ProtocolDefinition]], level: Int) async -> [[Strategy.Line]] {
        var units: [[Strategy.Line]] = []
        for match in matchAcrossVersions(perVersion, key: { ABIKey.makeUnwrappingType(for: $0.protocolName.node) }) {
            guard let header = await strategy.resolveProtocolHeader(elements: match.elements, level: level) else { continue }

            var bodyUnits: [[Strategy.Line]] = []
            bodyUnits += await memberListUnits(perVersion: associatedTypeMembers(elements: match.elements), scope: .container(match.key), level: level)
            for category in MemberCategory.allCases {
                bodyUnits += await memberListUnits(
                    perVersion: match.elements.enumerated().map { versionIndex, definition in
                        renderableMembers(definition, in: category, versionIndex: versionIndex)
                    },
                    scope: .container(match.key),
                    level: level
                )
            }

            let lines = strategy.assembleContainer(header: header, key: match.key, bodyUnits: bodyUnits, level: level)
            if !lines.isEmpty { units.append(lines) }
        }
        return units
    }

    // MARK: - Extensions
    //
    // Rendered per **container** — one (target, protocol, where clause,
    // retroactive) sub-group of an `ExtensionName` bucket, matched across the
    // axis with the exact key the differ uses
    // (`ABIDiffer.extensionContainerKey`, one source of truth).

    private func extensionBucketUnits(perVersion: [OrderedDictionary<ExtensionName, [ExtensionDefinition]>]) async -> [[Strategy.Line]] {
        let containersPerVersion = perVersion.map { extensionContainers(of: $0) }
        var units: [[Strategy.Line]] = []
        for match in matchAcrossVersions(containersPerVersion, key: { $0.key }) {
            // Same key ⇒ same (protocol, where, retroactive) on every version,
            // so the latest present version's representative describes the
            // container (for the two-sided axis: `new ?? old`).
            guard let latest = match.elements.reversed().compactMap({ $0 }).first else { continue }
            let header = strategy.resolveExtensionHeader(header: extensionHeaderText(for: latest), elements: match.elements)

            let level = 1
            var bodyUnits: [[Strategy.Line]] = []
            for category in MemberCategory.allCases {
                bodyUnits += await memberListUnits(
                    perVersion: match.elements.enumerated().map { versionIndex, container in
                        extensionRenderableMembers(container?.definitions, in: category, versionIndex: versionIndex)
                    },
                    scope: .container(match.key),
                    level: level
                )
            }

            let lines = strategy.assembleContainer(header: header, key: match.key, bodyUnits: bodyUnits, level: level)
            if !lines.isEmpty { units.append(lines) }
        }
        return units
    }

    /// Splits every `ExtensionName` bucket into its per-conformance /
    /// per-`where`-block containers, preserving first-seen order — same rule
    /// as `ABIDiffer.extensionContainerSnapshots`.
    private func extensionContainers(of buckets: OrderedDictionary<ExtensionName, [ExtensionDefinition]>) -> [ExtensionUnionContainer] {
        var containers: [ExtensionUnionContainer] = []
        for (name, definitions) in buckets {
            var containerIndexByKey: [ABIKey: Int] = [:]
            for definition in definitions {
                let containerKey = ABIDiffer.extensionContainerKey(for: name, of: definition)
                if let containerIndex = containerIndexByKey[containerKey] {
                    containers[containerIndex].definitions.append(definition)
                } else {
                    containerIndexByKey[containerKey] = containers.count
                    containers.append(ExtensionUnionContainer(key: containerKey, name: name, definitions: [definition]))
                }
            }
        }
        return containers
    }

    /// The container's header line (`extension X: P where …`), built from its
    /// first definition — any present version's representative describes the
    /// container, since the key freezes (protocol, where, retroactive).
    private func extensionHeaderText(for container: ExtensionUnionContainer) -> SemanticString {
        let representative = container.definitions.first
        return SemanticString {
            Keyword(.extension)
            Space()
            container.name.print()
            if let protocolName = representative?.conformingProtocolName {
                Standard(":")
                Space()
                protocolName.node.printSemantic(using: .default)
            }
            if let genericSignature = representative?.genericSignature {
                Space()
                genericSignature.printSemantic(using: .default)
            }
        }
    }

    // MARK: - Per-category renderable-member builders
    //
    // Identity keys use the same `MemberRecord` projections `ABIDiffer`
    // freezes into snapshots, so both strategies' fact lookups join exactly.
    // Every render closure is built at printer level 0 — see
    // `UnionRenderableMember`.

    private func variableMember(_ variable: VariableDefinition, versionIndex: Int) -> UnionRenderableMember {
        let version = versions[versionIndex]
        let record = MemberRecord.make(variable)
        return UnionRenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) {
            await version.printVariable(variable, level: 0)
        }
    }

    private func functionMember(_ function: FunctionDefinition, versionIndex: Int) -> UnionRenderableMember {
        let version = versions[versionIndex]
        let record = MemberRecord.make(function)
        return UnionRenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) {
            await version.printFunction(function, level: 0)
        }
    }

    private func subscriptMember(_ subscriptDefinition: SubscriptDefinition, versionIndex: Int) -> UnionRenderableMember {
        let version = versions[versionIndex]
        let record = MemberRecord.make(subscriptDefinition)
        return UnionRenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) {
            await version.printSubscript(subscriptDefinition, level: 0)
        }
    }

    /// The renderable members of one definition in `category`, in declaration
    /// order. Allocators and functions share the function builder (both are
    /// `FunctionDefinition`s, keyed identically by their mangled signature),
    /// mirroring the printer's `renderMember`.
    private func renderableMembers<EnclosingDefinition: Definition>(
        _ definition: EnclosingDefinition?,
        in category: MemberCategory,
        versionIndex: Int
    ) -> [UnionRenderableMember] {
        guard let definition else { return [] }
        return definition.members(in: category).map { member in
            switch member {
            case .allocator(let function), .function(let function):
                functionMember(function, versionIndex: versionIndex)
            case .variable(let variable):
                variableMember(variable, versionIndex: versionIndex)
            case .subscript(let subscriptDefinition):
                subscriptMember(subscriptDefinition, versionIndex: versionIndex)
            }
        }
    }

    /// The renderable members of `category` merged across an extension
    /// container's definitions, category-major, matching how `ABIDiffer` keys
    /// a container's merged member set.
    private func extensionRenderableMembers(
        _ definitions: [ExtensionDefinition]?,
        in category: MemberCategory,
        versionIndex: Int
    ) -> [UnionRenderableMember] {
        (definitions ?? []).flatMap { renderableMembers($0, in: category, versionIndex: versionIndex) }
    }

    private func fieldMembers(elements: [TypeDefinition?]) -> [[UnionRenderableMember]] {
        elements.enumerated().map { versionIndex, definition -> [UnionRenderableMember] in
            guard let definition else { return [] }
            let version = versions[versionIndex]
            if case .enum = definition.typeContextDescriptorWrapper {
                return definition.fields.enumerated().map { tag, field in
                    let record = MemberRecord.makeCase(field, tag: tag)
                    return UnionRenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) {
                        await version.printEnumCase(field, level: 0)
                    }
                }
            } else {
                return definition.fields.map { field in
                    let record = MemberRecord.make(field)
                    return UnionRenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) {
                        await version.printField(field, level: 0)
                    }
                }
            }
        }
    }

    private func deinitMembers(elements: [TypeDefinition?]) -> [[UnionRenderableMember]] {
        elements.enumerated().map { versionIndex, definition -> [UnionRenderableMember] in
            guard let definition, definition.hasDeallocator else { return [] }
            let version = versions[versionIndex]
            let record = MemberRecord.makeDeinit()
            return [UnionRenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) {
                version.printDeinit()
            }]
        }
    }

    private func associatedTypeMembers(elements: [ProtocolDefinition?]) -> [[UnionRenderableMember]] {
        elements.enumerated().map { versionIndex, definition -> [UnionRenderableMember] in
            guard let definition else { return [] }
            let version = versions[versionIndex]
            return definition.associatedTypes.map { name in
                let record = MemberRecord.makeAssociatedType(name)
                return UnionRenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) {
                    version.printAssociatedType(name)
                }
            }
        }
    }

    // MARK: - Member merging

    /// Merges one category's members across the axis and hands each match to
    /// the strategy. Empty units (a member that renders to nothing) are
    /// dropped so they never leave a stray marker or annotation.
    private func memberListUnits(
        perVersion: [[UnionRenderableMember]],
        scope: UnionMemberScope,
        level: Int
    ) async -> [[Strategy.Line]] {
        var units: [[Strategy.Line]] = []
        for match in matchAcrossVersions(perVersion, key: { $0.identityKey }) {
            for unit in await strategy.memberUnits(match: match, scope: scope, level: level) where !unit.isEmpty {
                units.append(unit)
            }
        }
        return units
    }

    // MARK: - Matching

    /// Matches element lists across all N versions by an `ABIKey`, returning
    /// entries in union render order: the newest version's elements in its
    /// order form the spine, then each older version (newest → oldest)
    /// appends its not-yet-seen keys in its own order — so a declaration
    /// absent from the newest version sits where its last-carrying version
    /// put it. Keys are first-wins within each version (emission included:
    /// a later same-keyed element is never emitted a second time), mirroring
    /// `ABIDiffer.keyed`.
    private func matchAcrossVersions<Element>(
        _ perVersion: [[Element]],
        key: (Element) -> ABIKey
    ) -> [UnionMatch<Element>] {
        let keyedPerVersion = perVersion.map { elements -> [ABIKey: Element] in
            var keyed: [ABIKey: Element] = [:]
            keyed.reserveCapacity(elements.count)
            for element in elements {
                let elementKey = key(element)
                if keyed[elementKey] == nil { keyed[elementKey] = element }
            }
            return keyed
        }

        var seen: Set<ABIKey> = []
        var orderedKeys: [ABIKey] = []
        for versionIndex in perVersion.indices.reversed() {
            for element in perVersion[versionIndex] {
                let elementKey = key(element)
                if seen.insert(elementKey).inserted {
                    orderedKeys.append(elementKey)
                }
            }
        }

        return orderedKeys.map { orderedKey in
            UnionMatch(key: orderedKey, elements: keyedPerVersion.map { $0[orderedKey] })
        }
    }
}
