import Foundation
import SwiftDeclaration
@_spi(Internals) import Demangling
import Dependencies
import MachOSwiftSection
@_spi(Internals) import MachOSymbols

/// The in-image declarations the exported-only filter (evolution proposal
/// `exported-only-interface`) needs in order to rule on an
/// `extension`: an extension has no descriptor symbol of its own, so it is
/// dropped exactly when it targets — or declares conformance to — a
/// declaration of THIS image whose descriptor is provably not exported.
/// Targets living in other images are unknowable here and are always kept.
///
/// Built by ``SwiftDeclarationPrinter/installExportFilterScope(types:protocols:)``
/// from the indexer's complete type / protocol tables — the symbol store
/// cannot stand in for those: a stripped image carries no symbol at all for
/// a non-exported type, so a symbol-derived "is this type in-image" test
/// would keep every extension of a dropped private type.
public struct ExportFilterScope: Sendable, Equatable {
    /// Names of the in-image types whose nominal type descriptor is not in
    /// the export trie. Structural (`TypeName`'s `Hashable`), so an
    /// `ExtensionName` minted into a different node store still matches.
    public var nonExportedTypeNames: Set<TypeName>

    /// Names of the in-image protocols whose protocol descriptor is not in
    /// the export trie.
    public var nonExportedProtocolNames: Set<ProtocolName>

    public static let empty = ExportFilterScope(nonExportedTypeNames: [], nonExportedProtocolNames: [])

    public init(nonExportedTypeNames: Set<TypeName>, nonExportedProtocolNames: Set<ProtocolName>) {
        self.nonExportedTypeNames = nonExportedTypeNames
        self.nonExportedProtocolNames = nonExportedProtocolNames
    }
}

// MARK: - Scope installation

extension SwiftDeclarationPrinter {
    /// Computes the ``ExportFilterScope`` for the given in-image definitions
    /// and installs it on this printer. `SwiftInterfaceBuilder.printRoot()`
    /// calls this with the indexer's complete tables whenever
    /// `printExportedDeclarationsOnly` is set; a host that drives the printer
    /// per definition (bypassing `printRoot`) installs its own scope the same
    /// way. With no scope installed the extension leg of the filter
    /// degrades to "keep" — the filter never drops on a guess.
    public func installExportFilterScope(types: some Sequence<TypeDefinition>, protocols: some Sequence<ProtocolDefinition>) {
        var scope = ExportFilterScope.empty
        for typeDefinition in types where exportVerdict(forTypeDefinition: typeDefinition) == false {
            scope.nonExportedTypeNames.insert(typeDefinition.typeName)
        }
        for protocolDefinition in protocols where exportVerdict(forProtocolDefinition: protocolDefinition) == false {
            scope.nonExportedProtocolNames.insert(protocolDefinition.protocolName)
        }
        exportFilterScope = scope
    }

    public func removeExportFilterScope() {
        exportFilterScope = .empty
    }
}

// MARK: - Declaration-level verdicts

extension SwiftDeclarationPrinter {
    /// Whether the type's nominal type descriptor (`…Mn`) has an export-trie
    /// entry: `true` / `false` are trie facts, `nil` means no verdict (the
    /// image carries no export information, or no evidence could be found).
    /// The descriptor is the one symbol every nominal type owns regardless
    /// of what else got exported — on the `SymbolTestsCore` fixture the
    /// exported `Mn` and `Ma` (metadata accessor) sets coincide exactly.
    public func exportVerdict(forTypeDefinition typeDefinition: TypeDefinition) -> Bool? {
        exportVerdict(
            descriptorOffset: typeDefinition.typeContextDescriptorWrapper.typeContextDescriptor.offset,
            nameNode: typeDefinition.typeName.node,
            descriptorKind: .nominalTypeDescriptor,
            descriptorSuffix: "Mn"
        )
    }

    /// Whether the protocol's descriptor (`…Mp`) has an export-trie entry;
    /// same tri-state as ``exportVerdict(forTypeDefinition:)``.
    public func exportVerdict(forProtocolDefinition protocolDefinition: ProtocolDefinition) -> Bool? {
        exportVerdict(
            descriptorOffset: protocolDefinition.protocolDescriptor.offset,
            nameNode: protocolDefinition.protocolName.node,
            descriptorKind: .protocolDescriptor,
            descriptorSuffix: "Mp"
        )
    }

    /// Two legs, authoritative first:
    ///
    /// 1. The symbol actually located AT the descriptor. Every exported
    ///    descriptor has a trie row at its offset, and an unstripped image
    ///    also carries a local symtab row for a non-exported one, so this leg
    ///    answers with the compiler's own spelling of the name — which is
    ///    what makes it authoritative: a type nested in a CONSTRAINED
    ///    extension (`extension Foo where A: P { public struct Nested {} }`)
    ///    mangles only the extension's own requirements into its context,
    ///    while the model's name node carries the full signature, so a
    ///    remangled name misses the trie and would drop an exported type.
    /// 2. Only when no symbol sits at the descriptor (a stripped image's
    ///    non-exported type): the remangled descriptor name against the trie,
    ///    which is complete even when the symtab is not. Restricted to
    ///    canonical contexts — a name involving an `.extension` context is
    ///    exactly the shape leg 1 exists for, and yields no verdict here.
    private func exportVerdict(descriptorOffset: Int, nameNode: NodeReference, descriptorKind: Node.Kind, descriptorSuffix: String) -> Bool? {
        @Dependency(\.symbolIndexStore) var symbolIndexStore
        if let symbolsAtDescriptor = symbolIndexStore.symbols(for: descriptorOffset, in: machO),
           let descriptorSymbol = symbolsAtDescriptor.first(where: { $0.name.isSwiftSymbol && $0.name.hasSuffix(descriptorSuffix) }) {
            return symbolIndexStore.isExported(name: descriptorSymbol.name, in: machO)
        }
        guard let symbolName = Self.descriptorSymbolName(for: nameNode, descriptorKind: descriptorKind) else { return nil }
        return symbolIndexStore.isExported(name: symbolName, in: machO)
    }

    /// Remangles a name node into the symbol name of its `descriptorKind`
    /// descriptor (`_$s<context>Mn` / `_$s<context>Mp`), or `nil` when the
    /// spelling cannot be trusted. The name node may arrive wrapped in a
    /// `.type` envelope, and a specialized definition's name is a
    /// bound-generic node (`Box<Int>`) — the descriptor belongs to the
    /// unbound nominal, so both wrappers are peeled first. A context chain
    /// through an `.extension` node is refused (see the verdict's leg 2).
    /// The remangling walks a transient tree materialized from the
    /// reference; nothing is interned or cached.
    static func descriptorSymbolName(for node: NodeReference, descriptorKind: Node.Kind) -> String? {
        var contextNode = node.materialize()
        if contextNode.kind == .type, let wrappedNode = contextNode.children.first {
            contextNode = wrappedNode
        }
        switch contextNode.kind {
        case .boundGenericStructure, .boundGenericClass, .boundGenericEnum, .boundGenericProtocol, .boundGenericOtherNominalType, .boundGenericTypeAlias:
            guard var nominalNode = contextNode.children.first else { return nil }
            if nominalNode.kind == .type, let wrappedNode = nominalNode.children.first {
                nominalNode = wrappedNode
            }
            contextNode = nominalNode
        default:
            break
        }
        guard !containsExtensionContext(contextNode) else { return nil }
        let descriptorNode = Node.createTransient(kind: descriptorKind, children: [contextNode])
        let globalNode = Node.createTransient(kind: .global, children: [descriptorNode])
        return try? mangleAsString(globalNode)
    }

    private static func containsExtensionContext(_ node: Node) -> Bool {
        if node.kind == .extension { return true }
        return node.children.contains { containsExtensionContext($0) }
    }
}

// MARK: - Exclusion predicates

extension SwiftDeclarationPrinter {
    var isExportFilterEnabled: Bool {
        configuration.printExportedDeclarationsOnly
    }

    /// A type is dropped only on a definitive negative verdict; `nil` keeps it.
    package func isExcludedByExportFilter(_ typeDefinition: TypeDefinition) -> Bool {
        isExportFilterEnabled && exportVerdict(forTypeDefinition: typeDefinition) == false
    }

    package func isExcludedByExportFilter(_ protocolDefinition: ProtocolDefinition) -> Bool {
        isExportFilterEnabled && exportVerdict(forProtocolDefinition: protocolDefinition) == false
    }

    /// An extension is dropped when its target (the extended type or
    /// protocol) or the protocol it declares conformance to is an in-image
    /// declaration the installed ``ExportFilterScope`` recorded as not
    /// exported. Targets outside the scope — other images' types, or any
    /// target when no scope is installed — keep the extension.
    ///
    /// The fixture survey behind this rule: every non-exported conformance
    /// descriptor (`…Mc`) in `SymbolTestsCore` involves a private type or
    /// protocol, so the conformance descriptor itself needs no separate
    /// query — a conformance of an exported type to an exported (or
    /// external) protocol is as exported as its parties.
    package func isExcludedByExportFilter(_ extensionDefinition: ExtensionDefinition) -> Bool {
        guard isExportFilterEnabled else { return false }
        let scope = exportFilterScope
        let extensionName = extensionDefinition.extensionName
        switch extensionName.kind {
        case .type(let typeKind):
            if scope.nonExportedTypeNames.contains(TypeName(node: extensionName.node, kind: typeKind)) {
                return true
            }
        case .protocol:
            if scope.nonExportedProtocolNames.contains(ProtocolName(node: extensionName.node)) {
                return true
            }
        case .typeAlias:
            break
        }
        if let conformingProtocolName = extensionDefinition.conformingProtocolName,
           scope.nonExportedProtocolNames.contains(conformingProtocolName) {
            return true
        }
        return false
    }

    /// A NON-conformance extension every member and nested declaration of
    /// which the filter drops renders as `extension Foo {}` — pure noise, so
    /// the whole block goes. A conformance extension is kept even with an
    /// empty body: the conformance clause is itself the declaration.
    /// Requires the definition to be indexed (members come from `index(in:)`).
    package func isEmptiedByExportFilter(_ extensionDefinition: ExtensionDefinition) -> Bool {
        guard isExportFilterEnabled,
              extensionDefinition.protocolConformanceDescriptor == nil,
              extensionDefinition.conformingProtocolName == nil else { return false }
        if !extensionDefinition.associatedTypes.isEmpty { return false }
        if extensionDefinition.orderedMembers.contains(where: { !isExcludedByExportFilter($0) }) { return false }
        if extensionDefinition.types.contains(where: { !isExcludedByExportFilter($0) }) { return false }
        if extensionDefinition.protocols.contains(where: { !isExcludedByExportFilter($0) }) { return false }
        return true
    }

    /// The member rule is the annotation rule of proposal 0008 turned into a
    /// drop: excluded only when EVERY symbol of the member (derived forms
    /// included) provably lacks a trie entry. `override` (reachable through
    /// the parent's dispatch thunk) and `@objc` (objc_msgSend) members carry
    /// zero exported symbols of their own while being perfectly callable,
    /// so both are kept, exactly as they are never annotated.
    package func isExcludedByExportFilter(_ member: OrderedMember) -> Bool {
        guard isExportFilterEnabled else { return false }
        switch member {
        case .allocator(let function), .function(let function):
            return isExcludedByExportFilter(isOverride: function.isOverride, isObjC: function.attributes.contains(.objc), symbolNames: [function.symbol.name])
        case .variable(let variable):
            return isExcludedByExportFilter(isOverride: variable.isOverride, isObjC: variable.attributes.contains(.objc), symbolNames: variable.accessors.map(\.symbol.name))
        case .subscript(let `subscript`):
            return isExcludedByExportFilter(isOverride: `subscript`.isOverride, isObjC: `subscript`.attributes.contains(.objc), symbolNames: `subscript`.accessors.map(\.symbol.name))
        }
    }

    /// Stored-field leg, mirroring the annotation's field leg in
    /// `renderModelFields`: a field whose accessor group never joined has no
    /// evidence and is kept ("not checkable", never "confirmed exported");
    /// `FieldDefinition` carries no attributes, so `@objc` is recognized by
    /// the accessor's `To` thunk in the symbol population. Enum cases never
    /// reach here — they own no symbols.
    package func isExcludedByExportFilter(field: FieldDefinition) -> Bool {
        guard isExportFilterEnabled, !field.accessors.isEmpty, !field.isOverride else { return false }
        @Dependency(\.symbolIndexStore) var symbolIndexStore
        let hasObjCEntryPoint = field.accessors.contains { symbolIndexStore.containsSymbol(named: $0.symbol.name + "To", in: machO) }
        return !hasObjCEntryPoint && exportVerdict(forSymbolNames: field.accessors.map(\.symbol.name)) == false
    }

    /// Top-level globals: no `override` / `@objc` at top level, so the bare
    /// symbol verdict decides.
    package func isExcludedByExportFilter(globalSymbolNames symbolNames: [String]) -> Bool {
        isExportFilterEnabled && exportVerdict(forSymbolNames: symbolNames) == false
    }

    private func isExcludedByExportFilter(isOverride: Bool, isObjC: Bool, symbolNames: [String]) -> Bool {
        !isOverride && !isObjC && exportVerdict(forSymbolNames: symbolNames) == false
    }
}
