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
    /// `printExportedDeclarationsOnly` or `marksOptionalContent` is set; a
    /// host that drives the printer per definition (bypassing `printRoot`)
    /// installs its own scope the same way, for a marked print as for a
    /// filtered one. With no scope installed the extension leg of the filter
    /// degrades to "keep" — the filter never drops on a guess — and a marked
    /// print marks no extension.
    public func installExportFilterScope(types: some Sequence<TypeDefinition>, protocols: some Sequence<ProtocolDefinition>) {
        var scope = ExportFilterScope.empty
        for typeDefinition in types where typeDefinition.exportStatus.isDefinitelyNotExported {
            scope.nonExportedTypeNames.insert(typeDefinition.typeName)
        }
        for protocolDefinition in protocols where protocolDefinition.exportStatus.isDefinitelyNotExported {
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
    ///
    /// The verdict itself is resolved once at construction and lives on the
    /// model as `TypeDefinition.exportStatus` (see ``ExportStatus``); this
    /// method is the tri-state projection of that fact, kept for callers
    /// written against the pre-flag shape.
    public func exportVerdict(forTypeDefinition typeDefinition: TypeDefinition) -> Bool? {
        typeDefinition.exportStatus.isExported
    }

    /// Whether the protocol's descriptor (`…Mp`) has an export-trie entry;
    /// same tri-state as ``exportVerdict(forTypeDefinition:)``.
    public func exportVerdict(forProtocolDefinition protocolDefinition: ProtocolDefinition) -> Bool? {
        protocolDefinition.exportStatus.isExported
    }
}

// MARK: - Exclusion predicates

extension SwiftDeclarationPrinter {
    /// Whether the predicates below rule at all: when the filter is on, and
    /// when marking, whatever `printExportedDeclarationsOnly` says — a
    /// marked print records what the filter rules out instead of leaving it
    /// out (`exportFilterVisibility(excluded:)`).
    var evaluatesExportFilter: Bool {
        configuration.printExportedDeclarationsOnly || configuration.marksOptionalContent
    }

    /// A type is dropped only on a definitive negative verdict; `nil` keeps it.
    package func isExcludedByExportFilter(_ typeDefinition: TypeDefinition) -> Bool {
        evaluatesExportFilter && typeDefinition.exportStatus.isDefinitelyNotExported
    }

    package func isExcludedByExportFilter(_ protocolDefinition: ProtocolDefinition) -> Bool {
        evaluatesExportFilter && protocolDefinition.exportStatus.isDefinitelyNotExported
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
        guard evaluatesExportFilter else { return false }
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
        guard evaluatesExportFilter,
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
        guard evaluatesExportFilter else { return false }
        switch member {
        case .allocator(let function), .function(let function):
            return isExcludedByExportFilter(function.resolvedObjCMemberFacts(trustingSelectorNameEvidence: trustsSelectorNameEvidence), symbolNames: [function.symbol.name])
        case .variable(let variable):
            return isExcludedByExportFilter(variable.resolvedObjCMemberFacts(trustingSelectorNameEvidence: trustsSelectorNameEvidence), symbolNames: variable.accessors.map(\.symbol.name))
        case .subscript(let `subscript`):
            return isExcludedByExportFilter(`subscript`.resolvedObjCMemberFacts(trustingSelectorNameEvidence: trustsSelectorNameEvidence), symbolNames: `subscript`.accessors.map(\.symbol.name))
        }
    }

    /// Stored-field leg, mirroring the annotation's field leg in
    /// `renderModelFields`: a field whose accessor group never joined has no
    /// evidence and is kept ("not checkable", never "confirmed exported");
    /// `FieldDefinition` carries no attributes, so `@objc` is recognized by
    /// the accessor's `To` thunk in the symbol population. Enum cases never
    /// reach here — they own no symbols.
    package func isExcludedByExportFilter(field: FieldDefinition) -> Bool {
        guard evaluatesExportFilter, !field.accessors.isEmpty, !field.isOverride else { return false }
        @Dependency(\.symbolIndexStore) var symbolIndexStore
        let hasObjCEntryPoint = field.accessors.contains { symbolIndexStore.containsSymbol(named: $0.symbol.name + "To", in: machO) }
        return !hasObjCEntryPoint && exportVerdict(forSymbolNames: field.accessors.map(\.symbol.name)) == false
    }

    /// Top-level globals: no `override` / `@objc` at top level, so the bare
    /// symbol verdict decides.
    package func isExcludedByExportFilter(globalSymbolNames symbolNames: [String]) -> Bool {
        evaluatesExportFilter && exportVerdict(forSymbolNames: symbolNames) == false
    }

    private func isExcludedByExportFilter(_ objcFacts: ResolvedObjCMemberFacts, symbolNames: [String]) -> Bool {
        !objcFacts.isOverride && !objcFacts.isObjC && exportVerdict(forSymbolNames: symbolNames) == false
    }

    /// Whether the filter rules out every declaration a type's or an
    /// extension's body prints after its nested definitions, and there is at
    /// least one. Only stored fields and members are ever ruled out; an enum
    /// case, a `deinit`, an associated type and an Objective-C instance
    /// variable never are, so any one of them answers `false`. Requires the
    /// definition to be indexed.
    ///
    /// When marking, the last line break of such a body is visible only while
    /// the filter is off; see `bodyAfterNestedDefinitions(of:content:)`.
    package func excludesEveryDeclarationAfterNestedDefinitions(of definition: some Definition) -> Bool {
        guard evaluatesExportFilter else { return false }
        let synthesizedPropertyWrapperMembers = synthesizedPropertyWrapperMembers(of: definition)
        var hasDeclaration = false
        if let typeDefinition = definition as? TypeDefinition {
            if typeDefinition.deallocatorSymbol != nil { return false }
            let isEnum = typeDefinition.typeName.kind == .enum
            for field in typeDefinition.fields where !field.flags.contains(.isArtificial) && !synthesizedPropertyWrapperMembers.hiddenFieldNames.contains(field.name) {
                if isEnum || !isExcludedByExportFilter(field: field) { return false }
                hasDeclaration = true
            }
        }
        if let extensionDefinition = definition as? ExtensionDefinition {
            if !extensionDefinition.associatedTypes.isEmpty || !extensionDefinition.unrepresentedObjCImplementationInstanceVariables.isEmpty { return false }
        }
        for member in definition.orderedMembers where !synthesizedPropertyWrapperMembers.contains(member) {
            if !isExcludedByExportFilter(member) { return false }
            hasDeclaration = true
        }
        return hasDeclaration
    }
}
