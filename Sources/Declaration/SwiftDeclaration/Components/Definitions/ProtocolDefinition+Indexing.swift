import Demangling
import MachOSwiftSection
import OrderedCollections
import SwiftStdlibToolbox
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

extension ProtocolDefinition: OnceIndexedDefinition {
    /// Resolves the requirements and their default implementations to
    /// members. Idempotent, and safe to call from several tasks at once: the
    /// first runs the pass, the others wait for it (`DefinitionIndexing`).
    package func index(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try DefinitionIndexing.index(self) {
            try runIndexingPass(in: machO)
        }
    }

    /// The pass `index(in:)` runs once. Synchronous on purpose, and it must
    /// never index another definition: `DefinitionIndexing` blocks the
    /// callers that arrive while it runs.
    private func runIndexingPass(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        let dumpedProtocol = try materializedProtocol(in: machO.context)
        let name = protocolName.name
        // The first of `symbols` whose first protocol is this one and that no
        // earlier requirement claimed — answered from the index's grouping of
        // the address by protocol, built once per address (evolution proposal
        // `faster-lazy-definition-indexing`); `symbols` is what the index
        // listed at its offset. Structurally keyed: references can come from
        // different stores, and store-identity equality would let the same
        // implementation symbol be claimed by two requirements.
        func _symbol(for symbols: Symbols, visitedNodes: borrowing OrderedSet<StructuralNodeReferenceKey> = []) throws -> DemangledSymbol? {
            for candidate in SymbolIndexStore.shared.symbols(for: symbols.offset, ownedBy: name, ownerKind: .protocol, printedWith: .interfaceTypeBuilderOnly, in: machO) {
                if !visitedNodes.contains(StructuralNodeReferenceKey(candidate.demangledNode)) {
                    return candidate
                }
            }
            return nil
        }
        associatedTypes = try protocolDescriptor.associatedTypes(in: machO.context)
        suppressedInvertibleProtocolsByAssociatedTypeName = SuppressedAssociatedTypeInference.suppressedInvertibleProtocolsByAssociatedTypeName(
            ofAssociatedTypesNamed: Set(associatedTypes),
            protocolNode: protocolName.node.materialize(),
            in: machO
        )

        var requirementMemberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [MemberSymbol]> = [:]
        var defaultImplementationMemberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [MemberSymbol]> = [:]

        var requirementVisitedNodes: OrderedSet<StructuralNodeReferenceKey> = []
        var defaultImplementationVisitedNodes: OrderedSet<StructuralNodeReferenceKey> = []

        var offsetOfPWT = 0

        for requirement in dumpedProtocol.requirements {
            offsetOfPWT.offset(of: StoredPointer.self)
            if requirement.layout.defaultImplementation.isValid {
                defaultedRequirementPWTOffsets.insert(offsetOfPWT)
            }
            guard let symbols = machO.symbols(offset: requirement.offset), let symbol = try? _symbol(for: symbols, visitedNodes: requirementVisitedNodes) else {
                strippedSymbolicRequirements.append(.init(requirement: requirement, pwtOffset: offsetOfPWT))
                continue
            }
            requirementVisitedNodes.append(StructuralNodeReferenceKey(symbol.demangledNode))
            addSymbol(.init(base: symbol, protocolWitnessTableOffset: offsetOfPWT), memberSymbolsByKind: &requirementMemberSymbolsByKind, inExtension: false)
            if let symbols = requirement.defaultImplementationSymbols(in: machO), let defaultImplementationSymbol = try _symbol(for: symbols, visitedNodes: defaultImplementationVisitedNodes) {
                defaultImplementationVisitedNodes.append(StructuralNodeReferenceKey(defaultImplementationSymbol.demangledNode))
                addSymbol(.init(base: defaultImplementationSymbol, protocolWitnessTableOffset: offsetOfPWT), memberSymbolsByKind: &defaultImplementationMemberSymbolsByKind, inExtension: true)
            }
        }

        setDefinitions(for: requirementMemberSymbolsByKind, inExtension: false)

        orderedMembers = OrderedMember.pwtOrdered(OrderedMember.allMembers(from: self))

        // Descriptor-derived synthesis is the FALLBACK only: when the module
        // was indexed by `SwiftDeclarationIndexer`, its container-unification
        // pass (evolution proposal 0007) already attached the symbol-scan
        // protocol-extension blocks here — a superset of what the requirement
        // walk above can resolve (the per-requirement default-implementation
        // resolution loses members to identical-code-folded addresses, which
        // is how the trailing copy used to render fewer members than the
        // extensions-block copy of the same block). Only a standalone
        // `ProtocolDefinition` (SPI use, no module indexer) still needs the
        // synthesis.
        if defaultImplementationExtensions.isEmpty {
            let extensionDefinition = ExtensionDefinition(extensionName: protocolName.extensionName, genericSignature: nil, protocolConformance: nil)

            extensionDefinition.setDefinitions(for: defaultImplementationMemberSymbolsByKind, inExtension: true)
            extensionDefinition.orderedMembers = OrderedMember.offsetOrdered(OrderedMember.allMembers(from: extensionDefinition))

            if extensionDefinition.hasMembers {
                defaultImplementationExtensions = [extensionDefinition]
            }
        }
    }
}
