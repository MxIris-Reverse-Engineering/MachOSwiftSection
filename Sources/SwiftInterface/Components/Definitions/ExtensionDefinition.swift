import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangle
import Semantic
import SwiftStdlibToolbox

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

extension MutableDefinition {
    func setDefintions(for memberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]>, inExtension: Bool) {
        for (kind, memberSymbols) in memberSymbolsByKind {
            switch kind {
            case .variable(inExtension, let isStatic, false):
                if isStatic {
                    self.staticVariables = DefinitionBuilder.variables(for: memberSymbols, fieldNames: [], isGlobalOrStatic: true)
                } else {
                    self.variables = DefinitionBuilder.variables(for: memberSymbols, fieldNames: [], isGlobalOrStatic: false)
                }
            case .allocator:
                self.allocators = DefinitionBuilder.allocators(for: memberSymbols)
            case .function(inExtension, let isStatic):
                if isStatic {
                    self.staticFunctions = DefinitionBuilder.functions(for: memberSymbols, isGlobalOrStatic: true)
                } else {
                    self.functions = DefinitionBuilder.functions(for: memberSymbols, isGlobalOrStatic: false)
                }
            case .subscript(inExtension, let isStatic):
                if isStatic {
                    self.staticSubscripts = DefinitionBuilder.subscripts(for: memberSymbols, isStatic: true)
                } else {
                    self.subscripts = DefinitionBuilder.subscripts(for: memberSymbols, isStatic: false)
                }
            default:
                break
            }
        }
    }
}

extension Definition {
    func addSymbol(_ symbol: DemangledSymbol, memberSymbolsByKind: inout OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]>, inExtension: Bool) {
        let node = symbol.demangledNode
        if node.contains(.variable) {
            if node.contains(.static) {
                if node.isStoredVariable {
                    memberSymbolsByKind[.variable(inExtension: inExtension, isStatic: true, isStorage: true), default: []].append(symbol)
                } else {
                    memberSymbolsByKind[.variable(inExtension: inExtension, isStatic: true, isStorage: false), default: []].append(symbol)
                }
            } else {
                memberSymbolsByKind[.variable(inExtension: inExtension, isStatic: false, isStorage: false), default: []].append(symbol)
            }
        } else if node.contains(.allocator) {
            memberSymbolsByKind[.allocator(inExtension: inExtension), default: []].append(symbol)
        } else if node.contains(.function) {
            if node.contains(.static) {
                memberSymbolsByKind[.function(inExtension: inExtension, isStatic: true), default: []].append(symbol)
            } else {
                memberSymbolsByKind[.function(inExtension: inExtension, isStatic: false), default: []].append(symbol)
            }
        } else if node.contains(.subscript) {
            if node.contains(.static) {
                memberSymbolsByKind[.subscript(inExtension: inExtension, isStatic: true), default: []].append(symbol)
            } else {
                memberSymbolsByKind[.subscript(inExtension: inExtension, isStatic: false), default: []].append(symbol)
            }
        }
    }
}
