import Demangling
import MachOSwiftSection
import OrderedCollections
import SwiftStdlibToolbox
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

extension ProtocolDefinition {
    package func index(in machO: some MachOSwiftSectionRepresentableWithCache) async throws {
        guard !isIndexed else { return }
        let dumpedProtocol = try materializedProtocol(in: machO)
        let name = protocolName.name
        // Structurally keyed: `demangleSymbolReference` returns references from
        // different stores, and store-identity equality would let the same
        // implementation symbol be claimed by two requirements.
        func _symbol(for symbols: Symbols, visitedNodes: borrowing OrderedSet<StructuralNodeReferenceKey> = []) throws -> DemangledSymbol? {
            for symbol in symbols {
                if let node = SymbolicDemangler.demangleSymbolReference(for: symbol, in: machO), let protocolNode = node.first(of: .protocol), protocolNode.print(using: .interfaceTypeBuilderOnly) == name, !visitedNodes.contains(StructuralNodeReferenceKey(node)) {
                    return .init(symbol: symbol, demangledNode: node)
                }
            }
            return nil
        }
        associatedTypes = try protocolDescriptor.associatedTypes(in: machO)

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
            let extensionDefinition = try ExtensionDefinition(extensionName: protocolName.extensionName, genericSignature: nil, protocolConformance: nil, in: machO)

            extensionDefinition.setDefinitions(for: defaultImplementationMemberSymbolsByKind, inExtension: true)
            extensionDefinition.orderedMembers = OrderedMember.offsetOrdered(OrderedMember.allMembers(from: extensionDefinition))

            if extensionDefinition.hasMembers {
                defaultImplementationExtensions = [extensionDefinition]
            }
        }

        isIndexed = true
    }
}
