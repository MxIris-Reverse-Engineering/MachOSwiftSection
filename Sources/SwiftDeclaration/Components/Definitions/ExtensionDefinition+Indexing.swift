import Demangling
import MachOSwiftSection
import OrderedCollections
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

extension ExtensionDefinition {
    package func index<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) async throws {
        guard !isIndexed else { return }

        // Cheap pre-check on the retained descriptor keeps the typealias-only
        // majority from materializing at all; the one materialization below
        // is this operation's single allowed one (proposal 0002). Both early
        // returns are COMPLETED indexings ("nothing to index"), so they must
        // set `isIndexed` — otherwise every later consumer (the printer's
        // three probes plus the diffable builder) re-enters the whole
        // materialization per print. A thrown materialization deliberately
        // leaves the flag unset so a failed read can be retried.
        guard protocolConformanceDescriptor != nil else {
            isIndexed = true
            return
        }
        guard let protocolConformance = try materializedProtocolConformance(in: machO), !protocolConformance.resilientWitnesses.isEmpty else {
            isIndexed = true
            return
        }

        // Structurally keyed: `demangleSymbolReference` returns references from
        // different stores, and store-identity equality would let the same
        // implementation symbol be claimed by two witnesses.
        func _symbol(for symbols: Symbols, typeName: String, visitedNodes: borrowing OrderedSet<StructuralNodeReferenceKey> = []) throws -> DemangledSymbol? {
            for symbol in symbols {
                if let node = SymbolicDemangler.demangleSymbolReference(for: symbol, in: machO), let protocolConformanceNode = node.first(of: .protocolConformance), let symbolTypeName = protocolConformanceNode.children.first?.print(using: .interfaceTypeBuilderOnly), symbolTypeName == typeName, !visitedNodes.contains(StructuralNodeReferenceKey(node)) {
                    return .init(symbol: symbol, demangledNode: node)
                }
            }
            return nil
        }
        var visitedNodes: OrderedSet<StructuralNodeReferenceKey> = []
        var memberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [MemberSymbol]> = [:]
        var defaultImplementationSymbolNames: Set<String> = []

        for resilientWitness in protocolConformance.resilientWitnesses {
            if let symbols = resilientWitness.implementationSymbols(in: machO), let symbol = try _symbol(for: symbols, typeName: extensionName.name, visitedNodes: visitedNodes) {
                _ = visitedNodes.append(StructuralNodeReferenceKey(symbol.demangledNode))
                addSymbol(.init(symbol), memberSymbolsByKind: &memberSymbolsByKind, inExtension: true)
            } else if let requirement = try resilientWitness.requirement(in: machO) {
                switch requirement {
                case .symbol(let symbol):
                    if let demangledNode = SymbolicDemangler.demangleSymbolReference(for: symbol, in: machO) {
                        addSymbol(.init(.init(symbol: symbol, demangledNode: demangledNode)), memberSymbolsByKind: &memberSymbolsByKind, inExtension: true)
                    }
                case .element(let element):
                    if let symbols = machO.symbols(offset: element.offset), let symbol = try _symbol(for: symbols, typeName: extensionName.name, visitedNodes: visitedNodes) {
                        _ = visitedNodes.append(StructuralNodeReferenceKey(symbol.demangledNode))
                        addSymbol(.init(symbol), memberSymbolsByKind: &memberSymbolsByKind, inExtension: true)
                    } else if let defaultImplementationSymbols = element.defaultImplementationSymbols(in: machO), let symbol = try _symbol(for: defaultImplementationSymbols, typeName: extensionName.name, visitedNodes: visitedNodes) {
                        _ = visitedNodes.append(StructuralNodeReferenceKey(symbol.demangledNode))
                        // The witness resolved through the requirement's
                        // DEFAULT implementation — the code lives in a
                        // protocol extension, not on the conforming type
                        // (evolution proposal 0007). Remember the symbol so
                        // the built member can carry the fact.
                        defaultImplementationSymbolNames.insert(symbol.name)
                        addSymbol(.init(symbol), memberSymbolsByKind: &memberSymbolsByKind, inExtension: true)
                    } else if !element.defaultImplementation.isNull {
                        missingSymbolWitnesses.append(resilientWitness)
                    } else if !resilientWitness.implementation.isNull {
                        missingSymbolWitnesses.append(resilientWitness)
                    } else {
                        missingSymbolWitnesses.append(resilientWitness)
                    }
                }
            } else if !resilientWitness.implementation.isNull {
                missingSymbolWitnesses.append(resilientWitness)
            } else {
                missingSymbolWitnesses.append(resilientWitness)
            }
        }

        setDefinitions(for: memberSymbolsByKind, inExtension: true)

        if !defaultImplementationSymbolNames.isEmpty {
            markProtocolExtensionDefaults(named: defaultImplementationSymbolNames)
        }

        orderedMembers = OrderedMember.offsetOrdered(OrderedMember.allMembers(from: self))

        isIndexed = true
    }

    /// Marks the members whose witness resolved through a protocol
    /// requirement's default implementation, matched back by mangled symbol
    /// name after `setDefinitions` built them.
    func markProtocolExtensionDefaults(named symbolNames: Set<String>) {
        for index in functions.indices where symbolNames.contains(functions[index].symbol.name) {
            functions[index].isProtocolExtensionDefault = true
        }
        for index in staticFunctions.indices where symbolNames.contains(staticFunctions[index].symbol.name) {
            staticFunctions[index].isProtocolExtensionDefault = true
        }
        for index in allocators.indices where symbolNames.contains(allocators[index].symbol.name) {
            allocators[index].isProtocolExtensionDefault = true
        }
        for index in constructors.indices where symbolNames.contains(constructors[index].symbol.name) {
            constructors[index].isProtocolExtensionDefault = true
        }
        for index in variables.indices where variables[index].accessors.contains(where: { symbolNames.contains($0.symbol.name) }) {
            variables[index].isProtocolExtensionDefault = true
        }
        for index in staticVariables.indices where staticVariables[index].accessors.contains(where: { symbolNames.contains($0.symbol.name) }) {
            staticVariables[index].isProtocolExtensionDefault = true
        }
        for index in subscripts.indices where subscripts[index].accessors.contains(where: { symbolNames.contains($0.symbol.name) }) {
            subscripts[index].isProtocolExtensionDefault = true
        }
        for index in staticSubscripts.indices where staticSubscripts[index].accessors.contains(where: { symbolNames.contains($0.symbol.name) }) {
            staticSubscripts[index].isProtocolExtensionDefault = true
        }
    }
}
