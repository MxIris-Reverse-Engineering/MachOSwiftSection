import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangle
import Semantic
import SwiftStdlibToolbox

struct ExtensionDefinition: Definition {
    enum Kind {
        case type(TypeKind)
        case `protocol`
        case typeAlias
    }

    let name: String

    let kind: Kind

    let genericSignature: Node?

    let protocolConformance: ProtocolConformance?

    let associatedType: AssociatedType?

    var allocators: [FunctionDefinition] = []

    var variables: [VariableDefinition] = []

    var functions: [FunctionDefinition] = []

    var staticVariables: [VariableDefinition] = []

    var staticFunctions: [FunctionDefinition] = []

    var missingSymbolWitnesses: [ResilientWitness] = []

    var hasMembers: Bool {
        !variables.isEmpty || !functions.isEmpty || !staticVariables.isEmpty || !staticFunctions.isEmpty || !allocators.isEmpty
    }

    @SemanticStringBuilder
    func printName() -> SemanticString {
        switch kind {
        case .type(.enum):
            TypeDeclaration(kind: .enum, name)
        case .type(.struct):
            TypeDeclaration(kind: .struct, name)
        case .type(.class):
            TypeDeclaration(kind: .class, name)
        case .protocol:
            TypeDeclaration(kind: .protocol, name)
        case .typeAlias:
            TypeDeclaration(kind: .other, name)
        }
    }

    init<MachO: MachOSwiftSectionRepresentableWithCache>(name: String, kind: Kind, genericSignature: Node?, protocolConformance: ProtocolConformance?, associatedType: AssociatedType?, in machO: MachO) throws {
        self.name = name
        self.kind = kind
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
                    memberSymbolsByKind[.staticVariable, default: []].append(node)
                } else {
                    memberSymbolsByKind[.variable, default: []].append(node)
                }
            } else if node.contains(.allocator) {
                memberSymbolsByKind[.allocator, default: []].append(node)
            } else if node.contains(.function) {
                if node.contains(.static) {
                    memberSymbolsByKind[.staticFunction, default: []].append(node)
                } else {
                    memberSymbolsByKind[.function, default: []].append(node)
                }
            }
        }

        for resilientWitness in protocolConformance.resilientWitnesses {
            if let symbols = try resilientWitness.implementationSymbols(in: machO), let node = try _node(for: symbols, typeName: name, visitedNodes: visitedNodes) {
                _ = visitedNodes.append(node)
                addNode(node)
            } else if let requirement = try resilientWitness.requirement(in: machO) {
                switch requirement {
                case .symbol(let symbol):
                    if let demangledNode = try? MetadataReader.demangleSymbol(for: symbol, in: machO) {
                        addNode(demangledNode)
                    }
                case .element(let element):
                    if let symbols = try Symbols.resolve(from: element.offset, in: machO), let node = try _node(for: symbols, typeName: name, visitedNodes: visitedNodes) {
                        _ = visitedNodes.append(node)
                        addNode(node)
                    } else if let defaultImplementationSymbols = try element.defaultImplementationSymbols(in: machO), let node = try _node(for: defaultImplementationSymbols, typeName: name, visitedNodes: visitedNodes) {
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
            case .variable:
                self.variables = DefinitionBuilder.variables(for: memberSymbols, fieldNames: [], isStatic: false)
            case .allocator:
                self.allocators = DefinitionBuilder.allocators(for: memberSymbols)
            case .function:
                self.functions = DefinitionBuilder.functions(for: memberSymbols, isStatic: false)
            case .staticVariable:
                self.staticVariables = DefinitionBuilder.variables(for: memberSymbols, fieldNames: [], isStatic: true)
            case .staticFunction:
                self.staticFunctions = DefinitionBuilder.functions(for: memberSymbols, isStatic: true)
            default:
                break
            }
        }
    }
}
