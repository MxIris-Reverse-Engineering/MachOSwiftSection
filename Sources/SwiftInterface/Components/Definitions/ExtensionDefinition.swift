import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangle
import Semantic
import SwiftStdlibToolbox

public struct ExtensionDefinition: Definition {
    public let extensionName: ExtensionName

    public let genericSignature: Node?

    public let protocolConformance: ProtocolConformance?

    public let associatedType: AssociatedType?

    public var types: [TypeDefinition] = []

    public var protocols: [ProtocolDefinition] = []

    public var allocators: [FunctionDefinition] = []

    public var constructors: [FunctionDefinition] = []

    public var variables: [VariableDefinition] = []

    public var functions: [FunctionDefinition] = []

    public var subscripts: [SubscriptDefinition] = []

    public var staticVariables: [VariableDefinition] = []

    public var staticFunctions: [FunctionDefinition] = []

    public var staticSubscripts: [SubscriptDefinition] = []

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
        func _node(for symbols: Symbols, typeName: String, visitedNodes: borrowing OrderedSet<Node> = []) throws -> Node? {
            for symbol in symbols {
                if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let protocolConformanceNode = node.first(of: .protocolConformance), let symbolTypeName = protocolConformanceNode.children.first?.print(using: .interfaceTypeBuilderOnly), symbolTypeName == typeName || PrimitiveTypeMappingCache.shared.entry(in: machO)?.primitiveType(for: typeName) == symbolTypeName, !visitedNodes.contains(node) {
                    return node
                }
            }
            return nil
        }
        var visitedNodes: OrderedSet<Node> = []
        var memberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [Node]> = [:]

        func addNode(_ node: Node) {
            if node.contains(.variable) {
                if node.contains(.static) {
                    if node.isStoredVariable {
                        memberSymbolsByKind[.variable(inExtension: true, isStatic: true, isStorage: true), default: []].append(node)
                    } else {
                        memberSymbolsByKind[.variable(inExtension: true, isStatic: true, isStorage: false), default: []].append(node)
                    }
                } else {
                    memberSymbolsByKind[.variable(inExtension: true, isStatic: false, isStorage: false), default: []].append(node)
                }
            } else if node.contains(.allocator) {
                memberSymbolsByKind[.allocator(inExtension: true), default: []].append(node)
            } else if node.contains(.function) {
                if node.contains(.static) {
                    memberSymbolsByKind[.function(inExtension: true, isStatic: true), default: []].append(node)
                } else {
                    memberSymbolsByKind[.function(inExtension: true, isStatic: false), default: []].append(node)
                }
            } else if node.contains(.subscript) {
                if node.contains(.static) {
                    memberSymbolsByKind[.subscript(inExtension: true, isStatic: true), default: []].append(node)
                } else {
                    memberSymbolsByKind[.subscript(inExtension: true, isStatic: false), default: []].append(node)
                }
            }
        }

        for resilientWitness in protocolConformance.resilientWitnesses {
            if let symbols = try resilientWitness.implementationSymbols(in: machO), let node = try _node(for: symbols, typeName: extensionName.name, visitedNodes: visitedNodes) {
                _ = visitedNodes.append(node)
                addNode(node)
            } else if let requirement = try resilientWitness.requirement(in: machO) {
                switch requirement {
                case .symbol(let symbol):
                    if let demangledNode = try? MetadataReader.demangleSymbol(for: symbol, in: machO) {
                        addNode(demangledNode)
                    }
                case .element(let element):
                    if let symbols = try Symbols.resolve(from: element.offset, in: machO), let node = try _node(for: symbols, typeName: extensionName.name, visitedNodes: visitedNodes) {
                        _ = visitedNodes.append(node)
                        addNode(node)
                    } else if let defaultImplementationSymbols = try element.defaultImplementationSymbols(in: machO), let node = try _node(for: defaultImplementationSymbols, typeName: extensionName.name, visitedNodes: visitedNodes) {
                        _ = visitedNodes.append(node)
                        addNode(node)
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

        for (kind, memberSymbols) in memberSymbolsByKind {
            switch kind {
            case .variable(true, let isStatic, false):
                if isStatic {
                    self.staticVariables = DefinitionBuilder.variables(for: memberSymbols, fieldNames: [], isGlobalOrStatic: true)
                } else {
                    self.variables = DefinitionBuilder.variables(for: memberSymbols, fieldNames: [], isGlobalOrStatic: false)
                }
            case .allocator:
                self.allocators = DefinitionBuilder.allocators(for: memberSymbols)
            case .function(true, let isStatic):
                if isStatic {
                    self.staticFunctions = DefinitionBuilder.functions(for: memberSymbols, isGlobalOrStatic: true)
                } else {
                    self.functions = DefinitionBuilder.functions(for: memberSymbols, isGlobalOrStatic: false)
                }
            case .subscript(true, let isStatic):
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
