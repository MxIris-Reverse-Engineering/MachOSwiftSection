import SwiftDeclaration
@_spi(Support) import SwiftIndexing
@_spi(Support) import SwiftPrinting
import SwiftDiffing
import SwiftDeclarationRendering
import MachOSwiftSection
import Semantic
import Demangling
import OrderedCollections

/// Renders a **full Swift interface annotated with diff markers** — a git-diff
/// style view of how the new binary's ABI surface differs from the old.
///
/// It is the rendering analogue of ``ABIDiffer``: where the differ produces a
/// machine-readable change list, this produces the *whole* interface (every
/// declaration, changed or not) with each line classified as `added` (`+`),
/// `removed` (`-`), or `unchanged` (a space). It is structure-driven — it walks
/// the two indexed models, matches declarations on the same `ABIKey` the differ
/// uses, and emits each member from its own per-member printer so a single
/// member's lines can carry its own marker. A modified member shows as its old
/// line (`-`) immediately followed by its new line (`+`).
///
/// The renderer deliberately produces a *classified* stream — a block-grouped
/// `[[DiffLine]]` — and never bakes a diff symbol in. How a ``DiffMarker``
/// becomes concrete output (git-diff prefixes, a unified-diff hunk, HTML, …) is
/// the job of a ``DiffFormat``; ``printAnnotatedInterface(format:)`` defaults to
/// ``DiffFormat/inline``, which reproduces the original git-diff output.
///
/// Surface is FULL: public, package, internal, and private declarations are all
/// rendered (private discriminators kept). Access-level splitting is a future
/// refinement, not a filter.
///
/// Build two ``SwiftDiffableInterfaceBuilder``s, `prepare()` each, then hand them
/// here. The two binaries may be different `MachO` types (e.g. a standalone
/// dylib vs a dyld-cache image), so the renderer is generic over both.
public final class SwiftDiffableInterfaceRenderer<
    OldMachO: FieldLayoutRenderable,
    NewMachO: FieldLayoutRenderable
>: Sendable {
    private let oldIndexer: SwiftDeclarationIndexer<OldMachO>
    private let newIndexer: SwiftDeclarationIndexer<NewMachO>
    private let oldPrinter: SwiftDeclarationPrinter<OldMachO>
    private let newPrinter: SwiftDeclarationPrinter<NewMachO>

    public init(old: SwiftDiffableInterfaceBuilder<OldMachO>, new: SwiftDiffableInterfaceBuilder<NewMachO>) {
        self.oldIndexer = old.indexer
        self.newIndexer = new.indexer
        self.oldPrinter = .init(in: old.machO)
        self.newPrinter = .init(in: new.machO)
    }

    // MARK: - Top level

    /// Produces the annotated interface in the chosen ``DiffFormat`` (default
    /// ``DiffFormat/inline``, which reproduces the original git-diff output). The
    /// classified stream comes from ``annotatedDiffBlocks()``; the format turns it
    /// into the final string.
    public func printAnnotatedInterface(format: DiffFormat = .inline) async -> SemanticString {
        await format.render(annotatedDiffBlocks())
    }

    /// The full classified diff as a block-grouped, single-line-split stream: the
    /// outer array is the top-level declaration blocks in render order (globals →
    /// types → protocols → extensions), each inner array is one block's lines.
    /// Empty blocks are dropped. This is the structured input every ``DiffFormat``
    /// consumes; expose it for callers that need the raw classification rather
    /// than a rendered string.
    @_spi(Support)
    public func annotatedDiffBlocks() async -> [[DiffLine]] {
        var blocks: [[DiffLine]] = []

        blocks += await renderGlobalVariables()
        blocks += await renderGlobalFunctions()
        blocks += await renderTypeListUnits(
            old: Array(oldIndexer.rootTypeDefinitions.values),
            new: Array(newIndexer.rootTypeDefinitions.values),
            level: 1
        )
        blocks += await renderProtocolListUnits(
            old: Array(oldIndexer.rootProtocolDefinitions.values),
            new: Array(newIndexer.rootProtocolDefinitions.values),
            level: 1
        )
        blocks += await renderExtensionBucketsUnits(
            old: oldIndexer.typeExtensionDefinitions, new: newIndexer.typeExtensionDefinitions
        )
        blocks += await renderExtensionBucketsUnits(
            old: oldIndexer.protocolExtensionDefinitions, new: newIndexer.protocolExtensionDefinitions
        )
        blocks += await renderExtensionBucketsUnits(
            old: oldIndexer.typeAliasExtensionDefinitions, new: newIndexer.typeAliasExtensionDefinitions
        )
        blocks += await renderExtensionBucketsUnits(
            old: oldIndexer.conformanceExtensionDefinitions, new: newIndexer.conformanceExtensionDefinitions
        )

        return blocks.filter { !$0.isEmpty }
    }

    // MARK: - Globals
    //
    // Each global member is its own top-level block (no enclosing container), so
    // the format separates them the same way it separates declarations.

    private func renderGlobalVariables() async -> [[DiffLine]] {
        await diffMembers(
            old: oldIndexer.globalVariableDefinitions.map { variableMember($0, printer: oldPrinter, level: 0) },
            new: newIndexer.globalVariableDefinitions.map { variableMember($0, printer: newPrinter, level: 0) },
            level: 0
        )
    }

    private func renderGlobalFunctions() async -> [[DiffLine]] {
        await diffMembers(
            old: oldIndexer.globalFunctionDefinitions.map { functionMember($0, printer: oldPrinter, level: 0) },
            new: newIndexer.globalFunctionDefinitions.map { functionMember($0, printer: newPrinter, level: 0) },
            level: 0
        )
    }

    // MARK: - Types

    /// One classified block per matched top-level type (each block already flat —
    /// header, body, and closing brace in one ordered line list). Used both at the
    /// top level (each block separated as a declaration) and for nested types
    /// (each block contributed as one body unit of its enclosing container).
    private func renderTypeListUnits(old: [TypeDefinition], new: [TypeDefinition], level: Int) async -> [[DiffLine]] {
        var units: [[DiffLine]] = []
        for pair in matchByKey(old, new, key: { ABIKey.makeUnwrappingType(for: $0.typeName.node) }) {
            let lines = await renderType(old: pair.old, new: pair.new, level: level)
            if !lines.isEmpty { units.append(lines) }
        }
        return units
    }

    private func renderType(old: TypeDefinition?, new: TypeDefinition?, level: Int) async -> [DiffLine] {
        guard old != nil || new != nil else { return [] }
        let marker: DiffMarker = old == nil ? .added : (new == nil ? .removed : .unchanged)

        let oldHeader = await header(old) { try await oldPrinter.printTypeHeader($0, level: level) }
        let newHeader = await header(new) { try await newPrinter.printTypeHeader($0, level: level) }

        let bodyUnits = await typeBodyUnits(old: old, new: new, level: level)
        return DiffContainerAssembler.assemble(oldHeader: oldHeader, newHeader: newHeader, marker: marker, bodyUnits: bodyUnits, level: level)
    }

    /// The body of a type, mirroring `printTypeDefinition`'s composition order:
    /// nested types, nested protocols, stored fields / enum cases, then the
    /// symbol-backed member categories, then `deinit`. Each category is diffed
    /// independently; a nil side contributes an empty list, so this one path
    /// serves added, removed, and common types alike. Returns one unit per
    /// member / nested declaration (units are flattened into the container block
    /// by ``DiffContainerAssembler/assemble(oldHeader:newHeader:marker:bodyUnits:level:)``).
    private func typeBodyUnits(old: TypeDefinition?, new: TypeDefinition?, level: Int) async -> [[DiffLine]] {
        var units: [[DiffLine]] = []

        units += await renderTypeListUnits(old: old?.typeChildren ?? [], new: new?.typeChildren ?? [], level: level + 1)
        units += await renderProtocolListUnits(old: old?.protocolChildren ?? [], new: new?.protocolChildren ?? [], level: level + 1)

        units += await diffMembers(old: fieldMembers(old, level: level, printer: oldPrinter), new: fieldMembers(new, level: level, printer: newPrinter), level: level)

        units += await diffMemberCategories(
            level: level,
            old: { renderableMembers(old, in: $0, printer: oldPrinter, level: level) },
            new: { renderableMembers(new, in: $0, printer: newPrinter, level: level) }
        )

        units += await diffMembers(old: deinitMembers(old, printer: oldPrinter), new: deinitMembers(new, printer: newPrinter), level: level)

        return units
    }

    // MARK: - Protocols

    private func renderProtocolListUnits(old: [ProtocolDefinition], new: [ProtocolDefinition], level: Int) async -> [[DiffLine]] {
        var units: [[DiffLine]] = []
        for pair in matchByKey(old, new, key: { ABIKey.makeUnwrappingType(for: $0.protocolName.node) }) {
            let lines = await renderProtocol(old: pair.old, new: pair.new, level: level)
            if !lines.isEmpty { units.append(lines) }
        }
        return units
    }

    private func renderProtocol(old: ProtocolDefinition?, new: ProtocolDefinition?, level: Int) async -> [DiffLine] {
        guard old != nil || new != nil else { return [] }
        let marker: DiffMarker = old == nil ? .added : (new == nil ? .removed : .unchanged)

        let oldHeader = await header(old) { try await oldPrinter.printProtocolHeader($0, level: level) }
        let newHeader = await header(new) { try await newPrinter.printProtocolHeader($0, level: level) }

        var units: [[DiffLine]] = []
        units += await diffMembers(old: associatedTypeMembers(old, printer: oldPrinter), new: associatedTypeMembers(new, printer: newPrinter), level: level)
        units += await diffMemberCategories(
            level: level,
            old: { renderableMembers(old, in: $0, printer: oldPrinter, level: level) },
            new: { renderableMembers(new, in: $0, printer: newPrinter, level: level) }
        )

        return DiffContainerAssembler.assemble(oldHeader: oldHeader, newHeader: newHeader, marker: marker, bodyUnits: units, level: level)
    }

    // MARK: - Extensions
    //
    // Extensions are diffed and rendered at the `ExtensionName` bucket level —
    // members across every `ExtensionDefinition` filed under one target are
    // merged, matching how `ABIDiffer` keys them. The header is the synthesized
    // `extension <Target>` (no per-conformance `: Protocol` clause yet, since the
    // bucket merges multiple conformances). TODO(P2): per-conformance attribution
    // so the annotated headers carry the `: Protocol` clause and `where` blocks.

    private func renderExtensionBucketsUnits(
        old: OrderedDictionary<ExtensionName, [ExtensionDefinition]>,
        new: OrderedDictionary<ExtensionName, [ExtensionDefinition]>
    ) async -> [[DiffLine]] {
        let oldBuckets = old.map { (name: $0.key, definitions: $0.value) }
        let newBuckets = new.map { (name: $0.key, definitions: $0.value) }
        var units: [[DiffLine]] = []
        for pair in matchByKey(oldBuckets, newBuckets, key: { ABIDiffer.extensionBucketKey(for: $0.name) }) {
            let lines = await renderExtensionBucket(old: pair.old, new: pair.new, level: 1)
            if !lines.isEmpty { units.append(lines) }
        }
        return units
    }

    private func renderExtensionBucket(
        old: (name: ExtensionName, definitions: [ExtensionDefinition])?,
        new: (name: ExtensionName, definitions: [ExtensionDefinition])?,
        level: Int
    ) async -> [DiffLine] {
        guard old != nil || new != nil else { return [] }
        let marker: DiffMarker = old == nil ? .added : (new == nil ? .removed : .unchanged)

        let extensionName = new?.name ?? old?.name
        let header: SemanticString
        if let extensionName {
            header = SemanticString {
                Keyword(.extension)
                Space()
                extensionName.print()
            }
        } else {
            header = SemanticString()
        }

        var units: [[DiffLine]] = []
        units += await diffMemberCategories(
            level: level,
            old: { renderableMembers(old?.definitions, in: $0, printer: oldPrinter, level: level) },
            new: { renderableMembers(new?.definitions, in: $0, printer: newPrinter, level: level) }
        )

        return DiffContainerAssembler.assemble(oldHeader: header, newHeader: header, marker: marker, bodyUnits: units, level: level)
    }

    // MARK: - Per-category renderable-member builders

    private func variableMember<MachO>(_ variable: VariableDefinition, printer: SwiftDeclarationPrinter<MachO>, level: Int) -> RenderableMember {
        let record = MemberRecord.make(variable)
        return RenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) { await printer.printVariable(variable, level: level) }
    }

    private func functionMember<MachO>(_ function: FunctionDefinition, printer: SwiftDeclarationPrinter<MachO>, level: Int) -> RenderableMember {
        let record = MemberRecord.make(function)
        return RenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) { await printer.printFunction(function, level: level) }
    }

    private func subscriptMember<MachO>(_ subscriptDefinition: SubscriptDefinition, printer: SwiftDeclarationPrinter<MachO>, level: Int) -> RenderableMember {
        let record = MemberRecord.make(subscriptDefinition)
        return RenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) { await printer.printSubscript(subscriptDefinition, level: level) }
    }

    /// Projects one `OrderedMember` to a `RenderableMember`, dispatching to the
    /// matching per-member builder. Allocators and functions share the function
    /// builder (both are `FunctionDefinition`s, keyed identically by their
    /// mangled signature), mirroring the printer's `renderMember`.
    private func renderableMember<MachO>(for member: OrderedMember, printer: SwiftDeclarationPrinter<MachO>, level: Int) -> RenderableMember {
        switch member {
        case .allocator(let function), .function(let function):
            functionMember(function, printer: printer, level: level)
        case .variable(let variable):
            variableMember(variable, printer: printer, level: level)
        case .subscript(let subscriptDefinition):
            subscriptMember(subscriptDefinition, printer: printer, level: level)
        }
    }

    /// The renderable members of one definition in `category`, in declaration
    /// order — the diff-side counterpart of the printer's `members(in:)` walk.
    private func renderableMembers<EnclosingDefinition: Definition, MachO>(_ definition: EnclosingDefinition?, in category: MemberCategory, printer: SwiftDeclarationPrinter<MachO>, level: Int) -> [RenderableMember] {
        guard let definition else { return [] }
        return definition.members(in: category).map { renderableMember(for: $0, printer: printer, level: level) }
    }

    /// The renderable members of `category` merged across an extension bucket,
    /// category-major (all definitions' members of this one category), matching
    /// how `ABIDiffer` keys a bucket's merged member set.
    private func renderableMembers<MachO>(_ definitions: [ExtensionDefinition]?, in category: MemberCategory, printer: SwiftDeclarationPrinter<MachO>, level: Int) -> [RenderableMember] {
        (definitions ?? []).flatMap { renderableMembers($0, in: category, printer: printer, level: level) }
    }

    private func fieldMembers<MachO>(_ definition: TypeDefinition?, level: Int, printer: SwiftDeclarationPrinter<MachO>) -> [RenderableMember] {
        guard let definition else { return [] }
        if case .enum = definition.type {
            return definition.fields.enumerated().map { index, field in
                let record = MemberRecord.makeCase(field, tag: index)
                return RenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) { await printer.printEnumCase(field, level: level) }
            }
        } else {
            return definition.fields.map { field in
                let record = MemberRecord.make(field)
                return RenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) { await printer.printField(field, level: level) }
            }
        }
    }

    private func deinitMembers<MachO>(_ definition: TypeDefinition?, printer: SwiftDeclarationPrinter<MachO>) -> [RenderableMember] {
        guard let definition, definition.hasDeallocator else { return [] }
        let record = MemberRecord.makeDeinit()
        return [RenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) { printer.printDeinit() }]
    }

    private func associatedTypeMembers<MachO>(_ definition: ProtocolDefinition?, printer: SwiftDeclarationPrinter<MachO>) -> [RenderableMember] {
        guard let definition else { return [] }
        return definition.associatedTypes.map { name in
            let record = MemberRecord.makeAssociatedType(name)
            return RenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) { printer.printAssociatedType(name) }
        }
    }

    // MARK: - Member diffing

    /// Diffs every `MemberCategory` in canonical order, concatenating the per-unit
    /// line lists. Both `old`/`new` map a category to that side's renderable
    /// members; driving the loop from `MemberCategory.allCases` keeps the category
    /// schedule identical to the printer's `printMembersByCategory`, so a member
    /// category can never be silently dropped from the diff view.
    private func diffMemberCategories(
        level: Int,
        old: (MemberCategory) -> [RenderableMember],
        new: (MemberCategory) -> [RenderableMember]
    ) async -> [[DiffLine]] {
        var units: [[DiffLine]] = []
        for category in MemberCategory.allCases {
            units += await diffMembers(old: old(category), new: new(category), level: level)
        }
        return units
    }

    /// Three-way set difference over one category's members, keyed by
    /// `identityKey` (matching `ABIDiffer.diffMembers`). Emits, in new order:
    /// unchanged members (` `), added members (`+`), and modified members as the
    /// old line (`-`) immediately followed by the new line (`+`). Removed members
    /// are appended at the category's end (`-`). Returns one unit (a `[DiffLine]`)
    /// per emitted member side; empty units (a member that renders to nothing) are
    /// dropped so they never leave a stray marker.
    private func diffMembers(old: [RenderableMember], new: [RenderableMember], level: Int) async -> [[DiffLine]] {
        let oldByKey = firstWinsKeyed(old)
        let newByKey = firstWinsKeyed(new)

        var units: [[DiffLine]] = []
        for newMember in new {
            if let oldMember = oldByKey[newMember.identityKey] {
                if oldMember.payloadKey != newMember.payloadKey {
                    // The payload key (a remangle) can differ while the rendered
                    // signature is byte-identical — e.g. a symbolic reference or
                    // private discriminator that the `.default` printing elides.
                    // Showing an identical `-`/`+` pair is pure noise, so collapse
                    // it to a single context line; the change-list still records
                    // the underlying ABI-key change for anyone who needs it.
                    let oldRendered = await oldMember.render()
                    let newRendered = await newMember.render()
                    if oldRendered.string == newRendered.string {
                        units.append(DiffMarking.markedLines(newRendered, marker: .unchanged, indentLevel: level))
                    } else {
                        units.append(DiffMarking.markedLines(oldRendered, marker: .removed, indentLevel: level))
                        units.append(DiffMarking.markedLines(newRendered, marker: .added, indentLevel: level))
                    }
                } else {
                    units.append(DiffMarking.markedLines(await newMember.render(), marker: .unchanged, indentLevel: level))
                }
            } else {
                units.append(DiffMarking.markedLines(await newMember.render(), marker: .added, indentLevel: level))
            }
        }
        var emittedRemoved: Set<ABIKey> = []
        for oldMember in old where newByKey[oldMember.identityKey] == nil {
            guard emittedRemoved.insert(oldMember.identityKey).inserted else { continue }
            units.append(DiffMarking.markedLines(await oldMember.render(), marker: .removed, indentLevel: level))
        }
        return units.filter { !$0.isEmpty }
    }

    // MARK: - Generic helpers

    private func header<EnclosingDefinition>(_ definition: EnclosingDefinition?, _ render: (EnclosingDefinition) async throws -> SemanticString) async -> SemanticString {
        guard let definition else { return SemanticString() }
        return (try? await render(definition)) ?? SemanticString()
    }

    /// Matches two element lists by an `ABIKey`, returning pairs in render order:
    /// every new element (matched with its old counterpart or `nil`) in new
    /// order, then every old-only element (as `(old, nil)`) in old order. Keys
    /// are first-wins on each side, mirroring `ABIDiffer.keyed`.
    private func matchByKey<Element>(_ old: [Element], _ new: [Element], key: (Element) -> ABIKey) -> [(old: Element?, new: Element?)] {
        let oldByKey = firstWinsKeyed(old.map { (key($0), $0) })
        let newByKey = firstWinsKeyed(new.map { (key($0), $0) })

        var pairs: [(old: Element?, new: Element?)] = []
        for element in new {
            pairs.append((old: oldByKey[key(element)], new: element))
        }
        var emitted: Set<ABIKey> = []
        for element in old {
            let elementKey = key(element)
            if newByKey[elementKey] != nil { continue }
            guard emitted.insert(elementKey).inserted else { continue }
            pairs.append((old: element, new: nil))
        }
        return pairs
    }

    private func firstWinsKeyed(_ members: [RenderableMember]) -> [ABIKey: RenderableMember] {
        var result: [ABIKey: RenderableMember] = [:]
        result.reserveCapacity(members.count)
        for member in members where result[member.identityKey] == nil {
            result[member.identityKey] = member
        }
        return result
    }

    private func firstWinsKeyed<Element>(_ pairs: [(ABIKey, Element)]) -> [ABIKey: Element] {
        var result: [ABIKey: Element] = [:]
        result.reserveCapacity(pairs.count)
        for (elementKey, element) in pairs where result[elementKey] == nil {
            result[elementKey] = element
        }
        return result
    }
}

/// One member projected for the diff renderer: its identity / payload keys (the
/// same projection `ABIDiffer` uses) plus a closure that renders just that
/// member to a standalone `SemanticString` (no indentation, no leading newline).
private struct RenderableMember {
    let identityKey: ABIKey
    let payloadKey: ABIKey
    let render: () async -> SemanticString

    init(identityKey: ABIKey, payloadKey: ABIKey, render: @escaping () async -> SemanticString) {
        self.identityKey = identityKey
        self.payloadKey = payloadKey
        self.render = render
    }
}
