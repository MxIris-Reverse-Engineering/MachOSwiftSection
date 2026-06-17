import SwiftDeclaration
@_spi(Support) import SwiftIndexing
@_spi(Support) import SwiftPrinting
import SwiftDiffing
import SwiftDeclarationRendering
import MachOSwiftSection
import Semantic
import Demangling
import OrderedCollections

/// Renders a **full Swift interface annotated with inline `+`/`-` markers** — a
/// git-diff-style view of how the new binary's ABI surface differs from the old.
///
/// It is the rendering analogue of ``ABIDiffer``: where the differ produces a
/// machine-readable change list, this produces the *whole* interface (every
/// declaration, changed or not) with each line prefixed by `+` (added), `-`
/// (removed), or a space (unchanged). It is structure-driven — it walks the two
/// indexed models, matches declarations on the same `ABIKey` the differ uses,
/// and emits each member from its own per-member printer so a single member's
/// lines can carry its own marker. A modified member shows as its old line
/// (`-`) immediately followed by its new line (`+`).
///
/// Surface is FULL: public, package, internal, and private declarations are all
/// rendered (private discriminators kept). Access-level splitting is a future
/// refinement, not a filter.
///
/// Build two ``SwiftDiffableInterfaceBuilder``s, `prepare()` each, then hand them
/// here. The two binaries may be different `MachO` types (e.g. a standalone
/// dylib vs a dyld-cache image), so the renderer is generic over both.
public final class SwiftDiffableInterfaceRenderer<
    OldMachO: MachOSwiftSectionRepresentableWithCache,
    NewMachO: MachOSwiftSectionRepresentableWithCache
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

    /// Produces the annotated interface. Top-level declarations are rendered in
    /// the order globals → types → protocols → extensions, each separated by a
    /// blank line. Every line begins with a `+`/`-`/` ` marker at column 0.
    public func printAnnotatedInterface() async -> SemanticString {
        var blocks: [SemanticString] = []

        blocks.append(contentsOf: await renderGlobalVariables())
        blocks.append(contentsOf: await renderGlobalFunctions())
        blocks.append(contentsOf: await renderTypeList(
            old: Array(oldIndexer.rootTypeDefinitions.values),
            new: Array(newIndexer.rootTypeDefinitions.values),
            level: 1
        ))
        blocks.append(contentsOf: await renderProtocolList(
            old: Array(oldIndexer.rootProtocolDefinitions.values),
            new: Array(newIndexer.rootProtocolDefinitions.values),
            level: 1
        ))
        blocks.append(contentsOf: await renderExtensionBuckets(
            old: oldIndexer.typeExtensionDefinitions, new: newIndexer.typeExtensionDefinitions
        ))
        blocks.append(contentsOf: await renderExtensionBuckets(
            old: oldIndexer.protocolExtensionDefinitions, new: newIndexer.protocolExtensionDefinitions
        ))
        blocks.append(contentsOf: await renderExtensionBuckets(
            old: oldIndexer.typeAliasExtensionDefinitions, new: newIndexer.typeAliasExtensionDefinitions
        ))
        blocks.append(contentsOf: await renderExtensionBuckets(
            old: oldIndexer.conformanceExtensionDefinitions, new: newIndexer.conformanceExtensionDefinitions
        ))

        return joinBlocks(blocks, separator: "\n\n")
    }

    // MARK: - Globals

    private func renderGlobalVariables() async -> [SemanticString] {
        await diffMembers(
            old: oldIndexer.globalVariableDefinitions.map { variableMember($0, printer: oldPrinter, level: 0) },
            new: newIndexer.globalVariableDefinitions.map { variableMember($0, printer: newPrinter, level: 0) },
            level: 0
        )
    }

    private func renderGlobalFunctions() async -> [SemanticString] {
        await diffMembers(
            old: oldIndexer.globalFunctionDefinitions.map { functionMember($0, printer: oldPrinter, level: 0) },
            new: newIndexer.globalFunctionDefinitions.map { functionMember($0, printer: newPrinter, level: 0) },
            level: 0
        )
    }

    // MARK: - Types

    private func renderTypeList(old: [TypeDefinition], new: [TypeDefinition], level: Int) async -> [SemanticString] {
        var blocks: [SemanticString] = []
        for pair in matchByKey(old, new, key: { ABIKey.makeUnwrappingType(for: $0.typeName.node) }) {
            let block = await renderType(old: pair.old, new: pair.new, level: level)
            if !block.string.isEmpty { blocks.append(block) }
        }
        return blocks
    }

    private func renderType(old: TypeDefinition?, new: TypeDefinition?, level: Int) async -> SemanticString {
        guard old != nil || new != nil else { return SemanticString() }
        let marker: DiffMarker = old == nil ? .added : (new == nil ? .removed : .unchanged)

        let oldHeader = await header(old) { try await oldPrinter.printTypeHeader($0, level: level) }
        let newHeader = await header(new) { try await newPrinter.printTypeHeader($0, level: level) }

        let bodyUnits = await typeBodyUnits(old: old, new: new, level: level)
        return assembleContainer(oldHeader: oldHeader, newHeader: newHeader, marker: marker, bodyUnits: bodyUnits, level: level)
    }

    /// The body of a type, mirroring `printTypeDefinition`'s composition order:
    /// nested types, nested protocols, stored fields / enum cases, then the
    /// symbol-backed member categories, then `deinit`. Each category is diffed
    /// independently; a nil side contributes an empty list, so this one path
    /// serves added, removed, and common types alike.
    private func typeBodyUnits(old: TypeDefinition?, new: TypeDefinition?, level: Int) async -> [SemanticString] {
        var units: [SemanticString] = []

        units += await renderTypeList(old: old?.typeChildren ?? [], new: new?.typeChildren ?? [], level: level + 1)
        units += await renderProtocolList(old: old?.protocolChildren ?? [], new: new?.protocolChildren ?? [], level: level + 1)

        units += await diffMembers(old: fieldMembers(old, level: level, printer: oldPrinter), new: fieldMembers(new, level: level, printer: newPrinter), level: level)

        units += await diffMembers(old: functionMembers(old?.allocators, printer: oldPrinter, level: level), new: functionMembers(new?.allocators, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: variableMembers(old?.variables, printer: oldPrinter, level: level), new: variableMembers(new?.variables, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: functionMembers(old?.functions, printer: oldPrinter, level: level), new: functionMembers(new?.functions, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: subscriptMembers(old?.subscripts, printer: oldPrinter, level: level), new: subscriptMembers(new?.subscripts, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: variableMembers(old?.staticVariables, printer: oldPrinter, level: level), new: variableMembers(new?.staticVariables, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: functionMembers(old?.staticFunctions, printer: oldPrinter, level: level), new: functionMembers(new?.staticFunctions, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: subscriptMembers(old?.staticSubscripts, printer: oldPrinter, level: level), new: subscriptMembers(new?.staticSubscripts, printer: newPrinter, level: level), level: level)

        units += await diffMembers(old: deinitMembers(old, printer: oldPrinter), new: deinitMembers(new, printer: newPrinter), level: level)

        return units
    }

    // MARK: - Protocols

    private func renderProtocolList(old: [ProtocolDefinition], new: [ProtocolDefinition], level: Int) async -> [SemanticString] {
        var blocks: [SemanticString] = []
        for pair in matchByKey(old, new, key: { ABIKey.makeUnwrappingType(for: $0.protocolName.node) }) {
            let block = await renderProtocol(old: pair.old, new: pair.new, level: level)
            if !block.string.isEmpty { blocks.append(block) }
        }
        return blocks
    }

    private func renderProtocol(old: ProtocolDefinition?, new: ProtocolDefinition?, level: Int) async -> SemanticString {
        guard old != nil || new != nil else { return SemanticString() }
        let marker: DiffMarker = old == nil ? .added : (new == nil ? .removed : .unchanged)

        let oldHeader = await header(old) { try await oldPrinter.printProtocolHeader($0, level: level) }
        let newHeader = await header(new) { try await newPrinter.printProtocolHeader($0, level: level) }

        var units: [SemanticString] = []
        units += await diffMembers(old: associatedTypeMembers(old, printer: oldPrinter), new: associatedTypeMembers(new, printer: newPrinter), level: level)
        units += await diffMembers(old: functionMembers(old?.allocators, printer: oldPrinter, level: level), new: functionMembers(new?.allocators, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: variableMembers(old?.variables, printer: oldPrinter, level: level), new: variableMembers(new?.variables, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: functionMembers(old?.functions, printer: oldPrinter, level: level), new: functionMembers(new?.functions, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: subscriptMembers(old?.subscripts, printer: oldPrinter, level: level), new: subscriptMembers(new?.subscripts, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: variableMembers(old?.staticVariables, printer: oldPrinter, level: level), new: variableMembers(new?.staticVariables, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: functionMembers(old?.staticFunctions, printer: oldPrinter, level: level), new: functionMembers(new?.staticFunctions, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: subscriptMembers(old?.staticSubscripts, printer: oldPrinter, level: level), new: subscriptMembers(new?.staticSubscripts, printer: newPrinter, level: level), level: level)

        return assembleContainer(oldHeader: oldHeader, newHeader: newHeader, marker: marker, bodyUnits: units, level: level)
    }

    // MARK: - Extensions
    //
    // Extensions are diffed and rendered at the `ExtensionName` bucket level —
    // members across every `ExtensionDefinition` filed under one target are
    // merged, matching how `ABIDiffer` keys them. The header is the synthesized
    // `extension <Target>` (no per-conformance `: Protocol` clause yet, since the
    // bucket merges multiple conformances). TODO(P2): per-conformance attribution
    // so the annotated headers carry the `: Protocol` clause and `where` blocks.

    private func renderExtensionBuckets(
        old: OrderedDictionary<ExtensionName, [ExtensionDefinition]>,
        new: OrderedDictionary<ExtensionName, [ExtensionDefinition]>
    ) async -> [SemanticString] {
        let oldBuckets = old.map { (name: $0.key, definitions: $0.value) }
        let newBuckets = new.map { (name: $0.key, definitions: $0.value) }
        var blocks: [SemanticString] = []
        for pair in matchByKey(oldBuckets, newBuckets, key: { ABIDiffer.extensionBucketKey(for: $0.name) }) {
            let block = await renderExtensionBucket(old: pair.old, new: pair.new, level: 1)
            if !block.string.isEmpty { blocks.append(block) }
        }
        return blocks
    }

    private func renderExtensionBucket(
        old: (name: ExtensionName, definitions: [ExtensionDefinition])?,
        new: (name: ExtensionName, definitions: [ExtensionDefinition])?,
        level: Int
    ) async -> SemanticString {
        guard old != nil || new != nil else { return SemanticString() }
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

        var units: [SemanticString] = []
        units += await diffMembers(old: extensionFunctionMembers(old?.definitions, \.allocators, printer: oldPrinter, level: level), new: extensionFunctionMembers(new?.definitions, \.allocators, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: extensionVariableMembers(old?.definitions, \.variables, printer: oldPrinter, level: level), new: extensionVariableMembers(new?.definitions, \.variables, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: extensionFunctionMembers(old?.definitions, \.functions, printer: oldPrinter, level: level), new: extensionFunctionMembers(new?.definitions, \.functions, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: extensionSubscriptMembers(old?.definitions, \.subscripts, printer: oldPrinter, level: level), new: extensionSubscriptMembers(new?.definitions, \.subscripts, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: extensionVariableMembers(old?.definitions, \.staticVariables, printer: oldPrinter, level: level), new: extensionVariableMembers(new?.definitions, \.staticVariables, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: extensionFunctionMembers(old?.definitions, \.staticFunctions, printer: oldPrinter, level: level), new: extensionFunctionMembers(new?.definitions, \.staticFunctions, printer: newPrinter, level: level), level: level)
        units += await diffMembers(old: extensionSubscriptMembers(old?.definitions, \.staticSubscripts, printer: oldPrinter, level: level), new: extensionSubscriptMembers(new?.definitions, \.staticSubscripts, printer: newPrinter, level: level), level: level)

        return assembleContainer(oldHeader: header, newHeader: header, marker: marker, bodyUnits: units, level: level)
    }

    // MARK: - Per-category renderable-member builders

    private func variableMember<M>(_ variable: VariableDefinition, printer: SwiftDeclarationPrinter<M>, level: Int) -> RenderableMember {
        let record = MemberRecord.make(variable)
        return RenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) { await printer.printVariable(variable, level: level) }
    }

    private func functionMember<M>(_ function: FunctionDefinition, printer: SwiftDeclarationPrinter<M>, level: Int) -> RenderableMember {
        let record = MemberRecord.make(function)
        return RenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) { await printer.printFunction(function, level: level) }
    }

    private func subscriptMember<M>(_ subscriptDefinition: SubscriptDefinition, printer: SwiftDeclarationPrinter<M>, level: Int) -> RenderableMember {
        let record = MemberRecord.make(subscriptDefinition)
        return RenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) { await printer.printSubscript(subscriptDefinition, level: level) }
    }

    private func variableMembers<M>(_ variables: [VariableDefinition]?, printer: SwiftDeclarationPrinter<M>, level: Int) -> [RenderableMember] {
        (variables ?? []).map { variableMember($0, printer: printer, level: level) }
    }

    private func functionMembers<M>(_ functions: [FunctionDefinition]?, printer: SwiftDeclarationPrinter<M>, level: Int) -> [RenderableMember] {
        (functions ?? []).map { functionMember($0, printer: printer, level: level) }
    }

    private func subscriptMembers<M>(_ subscripts: [SubscriptDefinition]?, printer: SwiftDeclarationPrinter<M>, level: Int) -> [RenderableMember] {
        (subscripts ?? []).map { subscriptMember($0, printer: printer, level: level) }
    }

    private func fieldMembers<M>(_ definition: TypeDefinition?, level: Int, printer: SwiftDeclarationPrinter<M>) -> [RenderableMember] {
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

    private func deinitMembers<M>(_ definition: TypeDefinition?, printer: SwiftDeclarationPrinter<M>) -> [RenderableMember] {
        guard let definition, definition.hasDeallocator else { return [] }
        let record = MemberRecord.makeDeinit()
        return [RenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) { printer.printDeinit() }]
    }

    private func associatedTypeMembers<M>(_ definition: ProtocolDefinition?, printer: SwiftDeclarationPrinter<M>) -> [RenderableMember] {
        guard let definition else { return [] }
        return definition.associatedTypes.map { name in
            let record = MemberRecord.makeAssociatedType(name)
            return RenderableMember(identityKey: record.identityKey, payloadKey: record.payloadKey) { printer.printAssociatedType(name) }
        }
    }

    private func extensionVariableMembers<M>(_ definitions: [ExtensionDefinition]?, _ keyPath: KeyPath<ExtensionDefinition, [VariableDefinition]>, printer: SwiftDeclarationPrinter<M>, level: Int) -> [RenderableMember] {
        (definitions ?? []).flatMap { variableMembers($0[keyPath: keyPath], printer: printer, level: level) }
    }

    private func extensionFunctionMembers<M>(_ definitions: [ExtensionDefinition]?, _ keyPath: KeyPath<ExtensionDefinition, [FunctionDefinition]>, printer: SwiftDeclarationPrinter<M>, level: Int) -> [RenderableMember] {
        (definitions ?? []).flatMap { functionMembers($0[keyPath: keyPath], printer: printer, level: level) }
    }

    private func extensionSubscriptMembers<M>(_ definitions: [ExtensionDefinition]?, _ keyPath: KeyPath<ExtensionDefinition, [SubscriptDefinition]>, printer: SwiftDeclarationPrinter<M>, level: Int) -> [RenderableMember] {
        (definitions ?? []).flatMap { subscriptMembers($0[keyPath: keyPath], printer: printer, level: level) }
    }

    // MARK: - Member diffing

    /// Three-way set difference over one category's members, keyed by
    /// `identityKey` (matching `ABIDiffer.diffMembers`). Emits, in new order:
    /// unchanged members (` `), added members (`+`), and modified members as the
    /// old line (`-`) immediately followed by the new line (`+`). Removed members
    /// are appended at the category's end (`-`).
    private func diffMembers(old: [RenderableMember], new: [RenderableMember], level: Int) async -> [SemanticString] {
        let oldByKey = firstWinsKeyed(old)
        let newByKey = firstWinsKeyed(new)

        var units: [SemanticString] = []
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
                        units.append(DiffMarking.markLines(newRendered, marker: .unchanged, indentLevel: level))
                    } else {
                        units.append(DiffMarking.markLines(oldRendered, marker: .removed, indentLevel: level))
                        units.append(DiffMarking.markLines(newRendered, marker: .added, indentLevel: level))
                    }
                } else {
                    units.append(DiffMarking.markLines(await newMember.render(), marker: .unchanged, indentLevel: level))
                }
            } else {
                units.append(DiffMarking.markLines(await newMember.render(), marker: .added, indentLevel: level))
            }
        }
        var emittedRemoved: Set<ABIKey> = []
        for oldMember in old where newByKey[oldMember.identityKey] == nil {
            guard emittedRemoved.insert(oldMember.identityKey).inserted else { continue }
            units.append(DiffMarking.markLines(await oldMember.render(), marker: .removed, indentLevel: level))
        }
        return units.filter { !$0.string.isEmpty }
    }

    // MARK: - Assembly

    /// Assembles a container block from its header(s), the marker for the
    /// container as a whole, and its already-marked body units.
    ///
    /// For an added/removed container every line carries the container marker.
    /// For a common container the header is unchanged unless it actually changed
    /// (e.g. a conformance or generic-signature edit), in which case the old
    /// header is shown as `-` and the new header as `+`; the body carries its own
    /// per-member markers.
    private func assembleContainer(oldHeader: SemanticString, newHeader: SemanticString, marker: DiffMarker, bodyUnits: [SemanticString], level: Int) -> SemanticString {
        let opening = bodyUnits.isEmpty ? " {}" : " {"
        let headerLevel = level - 1

        var headerBlocks: [SemanticString] = []
        switch marker {
        case .added:
            headerBlocks.append(DiffMarking.markLines(newHeader.appending(opening), marker: .added, indentLevel: headerLevel))
        case .removed:
            headerBlocks.append(DiffMarking.markLines(oldHeader.appending(opening), marker: .removed, indentLevel: headerLevel))
        case .unchanged:
            if oldHeader.string != newHeader.string {
                headerBlocks.append(DiffMarking.markLines(oldHeader.appending(opening), marker: .removed, indentLevel: headerLevel))
                headerBlocks.append(DiffMarking.markLines(newHeader.appending(opening), marker: .added, indentLevel: headerLevel))
            } else {
                headerBlocks.append(DiffMarking.markLines(newHeader.appending(opening), marker: .unchanged, indentLevel: headerLevel))
            }
        }

        var blocks = headerBlocks
        blocks.append(contentsOf: bodyUnits)
        if !bodyUnits.isEmpty {
            blocks.append(DiffMarking.markLines("}", marker: marker, indentLevel: headerLevel))
        }
        return joinBlocks(blocks, separator: "\n")
    }

    // MARK: - Generic helpers

    private func header<Definition>(_ definition: Definition?, _ render: (Definition) async throws -> SemanticString) async -> SemanticString {
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

    private func joinBlocks(_ blocks: [SemanticString], separator: SemanticString) -> SemanticString {
        var result = SemanticString()
        var isFirst = true
        for block in blocks where !block.string.isEmpty {
            if !isFirst { result.append(separator) }
            result.append(block)
            isFirst = false
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
