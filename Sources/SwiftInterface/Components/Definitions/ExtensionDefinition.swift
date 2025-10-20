import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangling
import Semantic
import SwiftStdlibToolbox
@_spi(Internals) import MachOSymbols

public final class ExtensionDefinition: Definition, MutableDefinition {
    public let extensionName: ExtensionName

    public let genericSignature: Node?

    public let protocolConformance: ProtocolConformance?

    public let associatedType: AssociatedType?

    @Mutex
    public var types: [TypeDefinition] = []

    @Mutex
    public var protocols: [ProtocolDefinition] = []

    @Mutex
    public var allocators: [FunctionDefinition] = []

    @Mutex
    public var constructors: [FunctionDefinition] = []

    @Mutex
    public var variables: [VariableDefinition] = []

    @Mutex
    public var functions: [FunctionDefinition] = []

    @Mutex
    public var subscripts: [SubscriptDefinition] = []

    @Mutex
    public var staticVariables: [VariableDefinition] = []

    @Mutex
    public var staticFunctions: [FunctionDefinition] = []

    @Mutex
    public var staticSubscripts: [SubscriptDefinition] = []

    @Mutex
    public var missingSymbolWitnesses: [ResilientWitness] = []

    public var hasMembers: Bool {
        !variables.isEmpty || !functions.isEmpty || !staticVariables.isEmpty || !staticFunctions.isEmpty || !allocators.isEmpty || !constructors.isEmpty || !staticSubscripts.isEmpty || !subscripts.isEmpty
    }

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(extensionName: ExtensionName, genericSignature: Node?, protocolConformance: ProtocolConformance?, associatedType: AssociatedType?, in machO: MachO) throws {
        self.extensionName = extensionName
        self.genericSignature = genericSignature
        self.protocolConformance = protocolConformance
        self.associatedType = associatedType
        guard let protocolConformance, !protocolConformance.resilientWitnesses.isEmpty else { return }
        func _symbol(for symbols: Symbols, typeName: String, visitedNodes: borrowing OrderedSet<Node> = []) throws -> DemangledSymbol? {
            for symbol in symbols {
                if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let protocolConformanceNode = node.first(of: .protocolConformance), let symbolTypeName = protocolConformanceNode.children.first?.print(using: .interfaceTypeBuilderOnly), symbolTypeName == typeName || PrimitiveTypeMappingCache.shared.entry(in: machO)?.primitiveType(for: typeName) == symbolTypeName, !visitedNodes.contains(node) {
                    return .init(symbol: symbol, demangledNode: node)
                }
            }
            return nil
        }
        var visitedNodes: OrderedSet<Node> = []
        var memberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]> = [:]

        for resilientWitness in protocolConformance.resilientWitnesses {
            if let symbols = try resilientWitness.implementationSymbols(in: machO), let symbol = try _symbol(for: symbols, typeName: extensionName.name, visitedNodes: visitedNodes) {
                _ = visitedNodes.append(symbol.demangledNode)
                addSymbol(symbol, memberSymbolsByKind: &memberSymbolsByKind, inExtension: true)
            } else if let requirement = try resilientWitness.requirement(in: machO) {
                switch requirement {
                case .symbol(let symbol):
                    if let demangledNode = try? MetadataReader.demangleSymbol(for: symbol, in: machO) {
                        addSymbol(.init(symbol: symbol, demangledNode: demangledNode), memberSymbolsByKind: &memberSymbolsByKind, inExtension: true)
                    }
                case .element(let element):
                    if let symbols = try Symbols.resolve(from: element.offset, in: machO), let symbol = try _symbol(for: symbols, typeName: extensionName.name, visitedNodes: visitedNodes) {
                        _ = visitedNodes.append(symbol.demangledNode)
                        addSymbol(symbol, memberSymbolsByKind: &memberSymbolsByKind, inExtension: true)
                    } else if let defaultImplementationSymbols = try element.defaultImplementationSymbols(in: machO), let symbol = try _symbol(for: defaultImplementationSymbols, typeName: extensionName.name, visitedNodes: visitedNodes) {
                        _ = visitedNodes.append(symbol.demangledNode)
                        addSymbol(symbol, memberSymbolsByKind: &memberSymbolsByKind, inExtension: true)
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

        setDefintions(for: memberSymbolsByKind, inExtension: true)
    }
}
