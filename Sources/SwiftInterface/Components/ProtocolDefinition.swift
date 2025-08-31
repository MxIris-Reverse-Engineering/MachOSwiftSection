import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangle
import Semantic
import SwiftStdlibToolbox

final class ProtocolDefinition: Sendable {
    let `protocol`: MachOSwiftSection.`Protocol`

    @Mutex
    weak var parent: TypeDefinition?

    @Mutex
    var extensionContext: ExtensionContext? = nil

    @Mutex
    var requirements: [ProtocolRequirementDefinition] = []

    @Mutex
    var defaultImplementationRequirements: [ProtocolRequirementDefinition] = []

    @Mutex
    var defaultImplementationExtensions: [ExtensionDefinition] = []

    init<MachO: MachOSwiftSectionRepresentableWithCache>(`protocol`: MachOSwiftSection.`Protocol`, in machO: MachO) throws {
        self.protocol = `protocol`
        func _name() throws -> SemanticString {
            try MetadataReader.demangleContext(for: .protocol(`protocol`.descriptor), in: machO).printSemantic(using: .interfaceType).replacingTypeNameOrOtherToTypeDeclaration()
        }
        let name = try _name().string
        func _node(for symbols: Symbols, visitedNodes: borrowing OrderedSet<Node> = []) throws -> Node? {
            for symbol in symbols {
                if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let protocolNode = node.first(of: .protocol), protocolNode.print(using: .interfaceType) == name, !visitedNodes.contains(node) {
                    return node
                }
            }
            return nil
        }
        var requirements: [ProtocolRequirementDefinition] = []
        var defaultImplementationRequirements: [ProtocolRequirementDefinition] = []
        var requirementVisitedNodes: OrderedSet<Node> = []
        var defaultImplementationVisitedNodes: OrderedSet<Node> = []
        var variableKindsByName: OrderedDictionary<String, Set<VariableKind>> = [:]
        var nodeAndRequirements: [(node: Node, requirement: ProtocolRequirement)] = []
        for requirement in `protocol`.requirements {
            guard let symbols = try Symbols.resolve(from: requirement.offset, in: machO), let node = try? _node(for: symbols, visitedNodes: requirementVisitedNodes) else { continue }
            nodeAndRequirements.append((node, requirement))
            if let variable = node.first(of: .variable), let name = variable.identifier, let variableKind = node.variableKind {
                variableKindsByName[name, default: []].insert(variableKind)
            }
            requirementVisitedNodes.append(node)
        }
        for (node, requirement) in nodeAndRequirements {
            let requirementDefinition: ProtocolRequirementDefinition
            if let variable = node.first(of: .variable), let name = variable.identifier, node.contains(.getter), let variableKinds = variableKindsByName[name] {
                requirementDefinition = .variable(VariableDefinition(node: variable, name: name, hasSetter: variableKinds.contains(.setter), hasModifyAccessor: variableKinds.contains(.modifyAccessor), isStatic: !requirement.flags.isInstance))
            } else if node.contains(.allocator) {
                requirementDefinition = .function(FunctionDefinition(node: node, name: "", kind: .allocator, isStatic: true))
            } else if let function = node.first(of: .function), let name = function.identifier {
                requirementDefinition = .function(FunctionDefinition(node: function, name: name, kind: .function, isStatic: !requirement.flags.isInstance))
            } else {
                continue
            }
            requirements.append(requirementDefinition)
            if let symbols = try requirement.defaultImplementationSymbols(in: machO), let node = try _node(for: symbols, visitedNodes: defaultImplementationVisitedNodes) {
                switch requirementDefinition {
                case .function(let function):
                    defaultImplementationRequirements.append(.function(.init(node: node, name: function.name, kind: function.kind, isStatic: function.isStatic)))
                case .variable(let variable):
                    defaultImplementationRequirements.append(.variable(.init(node: node, name: variable.name, hasSetter: variable.hasSetter, hasModifyAccessor: variable.hasModifyAccessor, isStatic: variable.isStatic)))
                }
                defaultImplementationVisitedNodes.append(node)
            }
        }
        self.requirements = requirements
        self.defaultImplementationRequirements = defaultImplementationRequirements
        var extensionDefinition = try ExtensionDefinition(name: name, kind: .protocol, genericSignature: nil, protocolConformance: nil, associatedType: nil, in: machO)
        for defaultImplementationRequirement in defaultImplementationRequirements {
            switch defaultImplementationRequirement {
            case .variable(let variableDefinition):
                if variableDefinition.isStatic {
                    extensionDefinition.staticVariables.append(variableDefinition)
                } else {
                    extensionDefinition.variables.append(variableDefinition)
                }
            case .function(let functionDefinition):
                switch functionDefinition.kind {
                case .function:
                    if functionDefinition.isStatic {
                        extensionDefinition.staticFunctions.append(functionDefinition)
                    } else {
                        extensionDefinition.functions.append(functionDefinition)
                    }
                case .allocator:
                    extensionDefinition.allocators.append(functionDefinition)
                case .deallocator:
                    break
                }
            }
        }
        if extensionDefinition.hasMembers {
            self.defaultImplementationExtensions = [extensionDefinition]
        }
    }
}
