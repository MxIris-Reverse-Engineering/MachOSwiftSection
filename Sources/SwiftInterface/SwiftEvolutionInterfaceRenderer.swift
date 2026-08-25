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

/// Renders the **union interface** of N ≥ 2 versions of one module, each
/// declaration annotated with its lifecycle across the version axis — the
/// N-way generalization of ``SwiftDiffableInterfaceRenderer``.
///
/// Division of labor (the load-bearing design decision):
///
/// - **Annotation facts come solely from `ABIEvolution`** via
///   ``EvolutionAnnotationIndex``. The renderer computes each declaration's
///   `ABIKey` with the same construction `ABIDiffer` freezes into snapshots
///   and looks its lineage up; it never re-derives events itself, so the
///   annotated interface can never disagree with the lineage report or the
///   JSON. A lookup miss IS the "present throughout, never changed" verdict
///   (`ABIEvolution` materializes changed lineages only) and renders with no
///   annotation.
/// - **Rendered text comes from the live models**: every declaration renders
///   from the LAST version that has it, through that version's own printer —
///   which is also why a modified member shows a single line (its newest
///   generation), with the older shape carried in the annotation phrase.
///
/// Union ordering is the N-way extension of the two-sided `matchByKey` rule:
/// the newest version's declaration order is the spine, and declarations
/// absent from the newest version are appended in the order of the most
/// recent version that still had them (scanning newest → oldest). Member
/// categories walk `MemberCategory.allCases` so the category schedule stays
/// identical to the printer and the two-sided renderer.
///
/// Surface is FULL, matching the two-sided renderer: public, package,
/// internal, and private declarations all render. Protocols' symbol-stripped
/// `pwtslot:` requirement records are deliberately NOT rendered (they carry no
/// declaration; same as `diff --interface`) — their changes remain visible in
/// the lineage report and JSON.
struct SwiftEvolutionInterfaceRenderer: Sendable {
    /// Oldest → newest, index-aligned with the evolution's version axis.
    private let versions: [any EvolutionVersionRendering]
    private let annotations: EvolutionAnnotationIndex

    init(versions: [any EvolutionVersionRendering], annotations: EvolutionAnnotationIndex) {
        self.versions = versions
        self.annotations = annotations
    }

    // MARK: - Top level

    /// The full classified stream: the outer array is the top-level
    /// declaration blocks in render order (globals → types → protocols →
    /// extensions, mirroring the two-sided renderer), each inner array one
    /// block's lines. Empty blocks are dropped.
    func annotatedBlocks() async -> [[EvolutionLine]] {
        var blocks: [[EvolutionLine]] = []

        blocks += await renderGlobalVariables()
        blocks += await renderGlobalFunctions()
        blocks += await renderTypeListUnits(perVersion: versions.map(\.rootTypeDefinitions), level: 1)
        blocks += await renderProtocolListUnits(perVersion: versions.map(\.rootProtocolDefinitions), level: 1)
        blocks += await renderExtensionBucketsUnits(perVersion: versions.map(\.typeExtensionDefinitions))
        blocks += await renderExtensionBucketsUnits(perVersion: versions.map(\.protocolExtensionDefinitions))
        blocks += await renderExtensionBucketsUnits(perVersion: versions.map(\.typeAliasExtensionDefinitions))
        blocks += await renderExtensionBucketsUnits(perVersion: versions.map(\.conformanceExtensionDefinitions))

        return blocks.filter { !$0.isEmpty }
    }

    // MARK: - Globals
    //
    // Each global member is its own top-level block (no enclosing container),
    // so the format separates them the same way it separates declarations.

    private func renderGlobalVariables() async -> [[EvolutionLine]] {
        await mergeMemberUnits(
            perVersion: versions.enumerated().map { versionIndex, unit in
                unit.globalVariableDefinitions.map { variableMember($0, versionIndex: versionIndex, level: 0) }
            },
            annotationScope: .global,
            level: 0
        )
    }

    private func renderGlobalFunctions() async -> [[EvolutionLine]] {
        await mergeMemberUnits(
            perVersion: versions.enumerated().map { versionIndex, unit in
                unit.globalFunctionDefinitions.map { functionMember($0, versionIndex: versionIndex, level: 0) }
            },
            annotationScope: .global,
            level: 0
        )
    }

    // MARK: - Types

    private func renderTypeListUnits(perVersion: [[TypeDefinition]], level: Int) async -> [[EvolutionLine]] {
        var units: [[EvolutionLine]] = []
        for match in matchAcrossVersions(perVersion, key: { ABIKey.makeUnwrappingType(for: $0.typeName.node) }) {
            let lines = await renderType(elements: match.elements, containerKey: match.key, level: level)
            if !lines.isEmpty { units.append(lines) }
        }
        return units
    }

    private func renderType(elements: [TypeDefinition?], containerKey: ABIKey, level: Int) async -> [EvolutionLine] {
        let header = await latestRenderableHeader(
            elements: elements,
            subject: { $0.typeName.name },
            kind: .type
        ) { versionIndex, definition in
            try await versions[versionIndex].printTypeHeader(definition, level: level)
        }
        // Every present version failed to render a header — members and braces
        // under no header line are not valid Swift, so the declaration drops
        // whole (each failure has already been dispatched as an event).
        guard let header else { return [] }

        let bodyUnits = await typeBodyUnits(elements: elements, containerKey: containerKey, level: level)
        return EvolutionContainerAssembler.assemble(
            header: header,
            annotation: annotations.containerAnnotation(forKey: containerKey),
            bodyUnits: bodyUnits,
            level: level
        )
    }

    /// The body of a type, mirroring the two-sided renderer's composition
    /// order: nested types, nested protocols, stored fields / enum cases, the
    /// symbol-backed member categories, then `deinit`. A `nil` version
    /// contributes an empty list, so this one path serves declarations that
    /// exist on any subset of the axis.
    private func typeBodyUnits(elements: [TypeDefinition?], containerKey: ABIKey, level: Int) async -> [[EvolutionLine]] {
        var units: [[EvolutionLine]] = []

        units += await renderTypeListUnits(perVersion: elements.map { $0?.typeChildren ?? [] }, level: level + 1)
        units += await renderProtocolListUnits(perVersion: elements.map { $0?.protocolChildren ?? [] }, level: level + 1)

        units += await mergeMemberUnits(
            perVersion: fieldMembers(elements: elements, level: level),
            annotationScope: .container(containerKey),
            level: level
        )

        for category in MemberCategory.allCases {
            units += await mergeMemberUnits(
                perVersion: elements.enumerated().map { versionIndex, definition in
                    renderableMembers(definition, in: category, versionIndex: versionIndex, level: level)
                },
                annotationScope: .container(containerKey),
                level: level
            )
        }

        units += await mergeMemberUnits(
            perVersion: deinitMembers(elements: elements),
            annotationScope: .container(containerKey),
            level: level
        )

        return units
    }

    // MARK: - Protocols

    private func renderProtocolListUnits(perVersion: [[ProtocolDefinition]], level: Int) async -> [[EvolutionLine]] {
        var units: [[EvolutionLine]] = []
        for match in matchAcrossVersions(perVersion, key: { ABIKey.makeUnwrappingType(for: $0.protocolName.node) }) {
            let lines = await renderProtocol(elements: match.elements, containerKey: match.key, level: level)
            if !lines.isEmpty { units.append(lines) }
        }
        return units
    }

    private func renderProtocol(elements: [ProtocolDefinition?], containerKey: ABIKey, level: Int) async -> [EvolutionLine] {
        let header = await latestRenderableHeader(
            elements: elements,
            subject: { $0.protocolName.name },
            kind: .protocol
        ) { versionIndex, definition in
            try await versions[versionIndex].printProtocolHeader(definition, level: level)
        }
        guard let header else { return [] }

        var units: [[EvolutionLine]] = []
        units += await mergeMemberUnits(
            perVersion: associatedTypeMembers(elements: elements),
            annotationScope: .container(containerKey),
            level: level
        )
        for category in MemberCategory.allCases {
            units += await mergeMemberUnits(
                perVersion: elements.enumerated().map { versionIndex, definition in
                    renderableMembers(definition, in: category, versionIndex: versionIndex, level: level)
                },
                annotationScope: .container(containerKey),
                level: level
            )
        }

        return EvolutionContainerAssembler.assemble(
            header: header,
            annotation: annotations.containerAnnotation(forKey: containerKey),
            bodyUnits: units,
            level: level
        )
    }

    // MARK: - Extensions
    //
    // Rendered per **container** — one (target, protocol, where clause,
    // retroactive) sub-group of an `ExtensionName` bucket, matched across the
    // axis with the exact key the differ uses (`ABIDiffer.extensionContainerKey`,
    // one source of truth), mirroring the two-sided renderer.

    private typealias EvolutionExtensionContainer = (key: ABIKey, name: ExtensionName, definitions: [ExtensionDefinition])

    private func renderExtensionBucketsUnits(
        perVersion: [OrderedDictionary<ExtensionName, [ExtensionDefinition]>]
    ) async -> [[EvolutionLine]] {
        let containersPerVersion = perVersion.map { extensionContainers(of: $0) }
        var units: [[EvolutionLine]] = []
        for match in matchAcrossVersions(containersPerVersion, key: { $0.key }) {
            let lines = await renderExtensionContainer(elements: match.elements, containerKey: match.key)
            if !lines.isEmpty { units.append(lines) }
        }
        return units
    }

    /// Splits every `ExtensionName` bucket into its per-conformance /
    /// per-`where`-block containers, preserving first-seen order — same rule
    /// as the two-sided renderer and `ABIDiffer.extensionContainerSnapshots`.
    private func extensionContainers(
        of buckets: OrderedDictionary<ExtensionName, [ExtensionDefinition]>
    ) -> [EvolutionExtensionContainer] {
        var containers: [EvolutionExtensionContainer] = []
        for (name, definitions) in buckets {
            var containerIndexByKey: [ABIKey: Int] = [:]
            for definition in definitions {
                let containerKey = ABIDiffer.extensionContainerKey(for: name, of: definition)
                if let containerIndex = containerIndexByKey[containerKey] {
                    containers[containerIndex].definitions.append(definition)
                } else {
                    containerIndexByKey[containerKey] = containers.count
                    containers.append((containerKey, name, [definition]))
                }
            }
        }
        return containers
    }

    private func renderExtensionContainer(
        elements: [EvolutionExtensionContainer?],
        containerKey: ABIKey
    ) async -> [EvolutionLine] {
        // The header renders from the latest present version's representative.
        // Same key ⇒ same (protocol, where, retroactive) on every version, so
        // any present version's representative describes the container.
        guard let latest = elements.reversed().compactMap({ $0 }).first else { return [] }
        let representative = latest.definitions.first
        let header = SemanticString {
            Keyword(.extension)
            Space()
            latest.name.print()
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

        let level = 1
        var units: [[EvolutionLine]] = []
        for category in MemberCategory.allCases {
            units += await mergeMemberUnits(
                perVersion: elements.enumerated().map { versionIndex, container in
                    extensionRenderableMembers(container?.definitions, in: category, versionIndex: versionIndex, level: level)
                },
                annotationScope: .container(containerKey),
                level: level
            )
        }

        return EvolutionContainerAssembler.assemble(
            header: header,
            annotation: annotations.containerAnnotation(forKey: containerKey),
            bodyUnits: units,
            level: level
        )
    }

    // MARK: - Per-category renderable-member builders
    //
    // Identity keys use the same `MemberRecord` projections `ABIDiffer`
    // freezes into snapshots, so the annotation lookup joins exactly.

    private func variableMember(_ variable: VariableDefinition, versionIndex: Int, level: Int) -> EvolutionRenderableMember {
        let unit = versions[versionIndex]
        return EvolutionRenderableMember(identityKey: MemberRecord.make(variable).identityKey) {
            await unit.printVariable(variable, level: level)
        }
    }

    private func functionMember(_ function: FunctionDefinition, versionIndex: Int, level: Int) -> EvolutionRenderableMember {
        let unit = versions[versionIndex]
        return EvolutionRenderableMember(identityKey: MemberRecord.make(function).identityKey) {
            await unit.printFunction(function, level: level)
        }
    }

    private func subscriptMember(_ subscriptDefinition: SubscriptDefinition, versionIndex: Int, level: Int) -> EvolutionRenderableMember {
        let unit = versions[versionIndex]
        return EvolutionRenderableMember(identityKey: MemberRecord.make(subscriptDefinition).identityKey) {
            await unit.printSubscript(subscriptDefinition, level: level)
        }
    }

    /// The renderable members of one definition in `category`, in declaration
    /// order. Allocators and functions share the function builder (both are
    /// `FunctionDefinition`s, keyed identically), mirroring the two-sided
    /// renderer and the printer's `renderMember`.
    private func renderableMembers<EnclosingDefinition: Definition>(
        _ definition: EnclosingDefinition?,
        in category: MemberCategory,
        versionIndex: Int,
        level: Int
    ) -> [EvolutionRenderableMember] {
        guard let definition else { return [] }
        return definition.members(in: category).map { member in
            switch member {
            case .allocator(let function), .function(let function):
                functionMember(function, versionIndex: versionIndex, level: level)
            case .variable(let variable):
                variableMember(variable, versionIndex: versionIndex, level: level)
            case .subscript(let subscriptDefinition):
                subscriptMember(subscriptDefinition, versionIndex: versionIndex, level: level)
            }
        }
    }

    /// The renderable members of `category` merged across an extension
    /// container's definitions, category-major, matching how `ABIDiffer` keys
    /// a container's merged member set.
    private func extensionRenderableMembers(
        _ definitions: [ExtensionDefinition]?,
        in category: MemberCategory,
        versionIndex: Int,
        level: Int
    ) -> [EvolutionRenderableMember] {
        (definitions ?? []).flatMap { renderableMembers($0, in: category, versionIndex: versionIndex, level: level) }
    }

    private func fieldMembers(elements: [TypeDefinition?], level: Int) -> [[EvolutionRenderableMember]] {
        elements.enumerated().map { versionIndex, definition -> [EvolutionRenderableMember] in
            guard let definition else { return [] }
            let unit = versions[versionIndex]
            if case .enum = definition.typeContextDescriptorWrapper {
                return definition.fields.enumerated().map { tag, field in
                    EvolutionRenderableMember(identityKey: MemberRecord.makeCase(field, tag: tag).identityKey) {
                        await unit.printEnumCase(field, level: level)
                    }
                }
            } else {
                return definition.fields.map { field in
                    EvolutionRenderableMember(identityKey: MemberRecord.make(field).identityKey) {
                        await unit.printField(field, level: level)
                    }
                }
            }
        }
    }

    private func deinitMembers(elements: [TypeDefinition?]) -> [[EvolutionRenderableMember]] {
        elements.enumerated().map { versionIndex, definition -> [EvolutionRenderableMember] in
            guard let definition, definition.hasDeallocator else { return [] }
            let unit = versions[versionIndex]
            return [EvolutionRenderableMember(identityKey: MemberRecord.makeDeinit().identityKey) {
                unit.printDeinit()
            }]
        }
    }

    private func associatedTypeMembers(elements: [ProtocolDefinition?]) -> [[EvolutionRenderableMember]] {
        elements.enumerated().map { versionIndex, definition -> [EvolutionRenderableMember] in
            guard let definition else { return [] }
            let unit = versions[versionIndex]
            return definition.associatedTypes.map { name in
                EvolutionRenderableMember(identityKey: MemberRecord.makeAssociatedType(name).identityKey) {
                    unit.printAssociatedType(name)
                }
            }
        }
    }

    // MARK: - Member merging

    private enum AnnotationScope {
        case global
        case container(ABIKey)
    }

    /// N-way member merge for one category: match by `identityKey`, render
    /// each matched member from its latest present version, and attach its
    /// lineage annotation. Returns one unit per member; empty renderings are
    /// dropped so they never leave a stray annotation.
    private func mergeMemberUnits(
        perVersion: [[EvolutionRenderableMember]],
        annotationScope: AnnotationScope,
        level: Int
    ) async -> [[EvolutionLine]] {
        var units: [[EvolutionLine]] = []
        for match in matchAcrossVersions(perVersion, key: { $0.identityKey }) {
            guard let latest = match.elements.reversed().compactMap({ $0 }).first else { continue }
            let rendered = await latest.render()
            let annotation: EvolutionAnnotation? = switch annotationScope {
            case .global:
                annotations.globalAnnotation(forKey: match.key)
            case .container(let containerKey):
                annotations.memberAnnotation(forContainerKey: containerKey, memberKey: match.key)
            }
            let lines = EvolutionMarking.annotatedLines(rendered, annotation: annotation, indentLevel: level)
            if !lines.isEmpty { units.append(lines) }
        }
        return units
    }

    // MARK: - Generic helpers

    /// Matches element lists across all N versions by an `ABIKey`, returning
    /// entries in union render order: the newest version's elements in its
    /// order form the spine, then each older version (newest → oldest)
    /// appends its not-yet-seen keys in its own order — so a declaration
    /// absent from the newest version sits where its last-carrying version
    /// put it. Keys are first-wins within each version, mirroring
    /// `ABIDiffer.keyed`.
    private func matchAcrossVersions<Element>(
        _ perVersion: [[Element]],
        key: (Element) -> ABIKey
    ) -> [(key: ABIKey, elements: [Element?])] {
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
            (key: orderedKey, elements: keyedPerVersion.map { $0[orderedKey] })
        }
    }

    /// Renders a container header from the latest version that can: walks the
    /// present versions newest → oldest, returning the first header that
    /// renders. Each failure is dispatched on ITS version's dispatcher
    /// (`definitionPrintFailed`, with the declaration named so the operator
    /// can see what degraded — issue #102's lesson), and `nil` comes back only
    /// when every present version failed, in which case the caller drops the
    /// whole declaration (members under no header are not valid Swift — the
    /// two-sided renderer's drop-whole rule, generalized to N sides).
    private func latestRenderableHeader<EnclosingDefinition>(
        elements: [EnclosingDefinition?],
        subject: (EnclosingDefinition) -> String,
        kind: SwiftIndexEvents.PrintingDefinitionKind,
        render: (Int, EnclosingDefinition) async throws -> SemanticString
    ) async -> SemanticString? {
        for versionIndex in elements.indices.reversed() {
            guard let definition = elements[versionIndex] else { continue }
            do {
                return try await render(versionIndex, definition)
            } catch {
                versions[versionIndex].eventDispatcher.dispatch(
                    .definitionPrintFailed(
                        context: .init(name: subject(definition), kind: kind),
                        error: error
                    )
                )
            }
        }
        return nil
    }
}

/// One member projected for the evolution renderer: its identity key (the
/// same projection `ABIDiffer` uses, which is what joins it to its lineage)
/// plus a closure that renders just that member to a standalone
/// `SemanticString` through its own version's printer.
private struct EvolutionRenderableMember {
    let identityKey: ABIKey
    let render: () async -> SemanticString

    init(identityKey: ABIKey, render: @escaping () async -> SemanticString) {
        self.identityKey = identityKey
        self.render = render
    }
}
