import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangle
import Semantic
import SwiftStdlibToolbox

public final class ProtocolDefinition: Sendable {
    public let `protocol`: MachOSwiftSection.`Protocol`

    @Mutex
    public weak var parent: TypeDefinition?

    @Mutex
    public var extensionContext: ExtensionContext? = nil

    @Mutex
    public var requirements: [ProtocolRequirementDefinition] = []

    @Mutex
    public var defaultImplementationRequirements: [ProtocolRequirementDefinition] = []

    @Mutex
    public var defaultImplementationExtensions: [ExtensionDefinition] = []

    @Mutex
    public var associatedTypes: [String] = []

    public var hasMembers: Bool {
        !requirements.isEmpty || !associatedTypes.isEmpty
    }

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(`protocol`: MachOSwiftSection.`Protocol`, in machO: MachO) throws {
        self.protocol = `protocol`
        func _name() throws -> SemanticString {
            try MetadataReader.demangleContext(for: .protocol(`protocol`.descriptor), in: machO).printSemantic(using: .interfaceTypeBuilderOnly).replacingTypeNameOrOtherToTypeDeclaration()
        }
        let name = try _name().string
        func _node(for symbols: Symbols, visitedNodes: borrowing OrderedSet<Node> = []) throws -> Node? {
            for symbol in symbols {
                if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let protocolNode = node.first(of: .protocol), protocolNode.print(using: .interfaceTypeBuilderOnly) == name, !visitedNodes.contains(node) {
                    return node
                }
            }
            return nil
        }
        self.associatedTypes = try `protocol`.descriptor.associatedTypes(in: machO)
        
        var requirements: [ProtocolRequirementDefinition] = []
        var defaultImplementationRequirements: [ProtocolRequirementDefinition] = []
        
        var requirementVisitedNodes: OrderedSet<Node> = []
        var defaultImplementationVisitedNodes: OrderedSet<Node> = []
        
        var variableKindsByName: OrderedDictionary<String, Set<AccessorKind>> = [:]
        var defaultImplementationVariableKindsByName: OrderedDictionary<String, Set<AccessorKind>> = [:]
        
        var subscriptKindsByName: OrderedDictionary<Node, Set<AccessorKind>> = [:]
        var defaultImplementationSubscriptKindsByName: OrderedDictionary<Node, Set<AccessorKind>> = [:]
        
        var nodeAndRequirements: [(node: Node, requirement: ProtocolRequirement)] = []
        var defaultImplementationNodeAndRequirements: [(node: Node, requirement: ProtocolRequirement)] = []
        
        for requirement in `protocol`.requirements {
            guard let symbols = try Symbols.resolve(from: requirement.offset, in: machO), let node = try? _node(for: symbols, visitedNodes: requirementVisitedNodes) else { continue }
            nodeAndRequirements.append((node, requirement))
            if let variable = node.first(of: .variable), let name = variable.identifier, let kind = node.accessorKind {
                variableKindsByName[name, default: []].insert(kind)
            } else if let `subscript` = node.first(of: .subscript), let kind = node.accessorKind {
                subscriptKindsByName[`subscript`, default: []].insert(kind)
            }
            requirementVisitedNodes.append(node)
        }
        for (node, requirement) in nodeAndRequirements {
            let requirementDefinition: ProtocolRequirementDefinition
            let isStatic = !requirement.flags.isInstance
            if let variable = node.first(of: .variable), let name = variable.identifier, node.contains(.getter), let kinds = variableKindsByName[name] {
                requirementDefinition = .variable(VariableDefinition(node: node, name: name, hasSetter: kinds.contains(.setter), hasModifyAccessor: kinds.contains(.modifyAccessor), isGlobalOrStatic: isStatic, isStored: false))
            } else if let `subscript` = node.first(of: .subscript), node.contains(.getter), let kinds = subscriptKindsByName[`subscript`] {
                requirementDefinition = .subscript(SubscriptDefinition(node: node, hasSetter: kinds.contains(.setter), hasReadAccessor: kinds.contains(.readAccessor), hasModifyAccessor: kinds.contains(.modifyAccessor), isStatic: isStatic))
            } else if node.contains(.allocator) {
                requirementDefinition = .function(FunctionDefinition(node: node, name: "", kind: .allocator, isGlobalOrStatic: true))
            } else if let function = node.first(of: .function), let name = function.identifier {
                requirementDefinition = .function(FunctionDefinition(node: node, name: name, kind: .function, isGlobalOrStatic: isStatic))
            } else {
                continue
            }
            requirements.append(requirementDefinition)
            if let symbols = try requirement.defaultImplementationSymbols(in: machO), let node = try _node(for: symbols, visitedNodes: defaultImplementationVisitedNodes) {
                if let variable = node.first(of: .variable), let name = variable.identifier, let kind = node.accessorKind {
                    defaultImplementationVariableKindsByName[name, default: []].insert(kind)
                } else if let `subscript` = node.first(of: .subscript), let kind = node.accessorKind {
                    defaultImplementationSubscriptKindsByName[`subscript`, default: []].insert(kind)
                }
                
                defaultImplementationVisitedNodes.append(node)
                defaultImplementationNodeAndRequirements.append((node, requirement))
            }
        }

        self.requirements = requirements

        for (node, requirement) in defaultImplementationNodeAndRequirements {
            let requirementDefinition: ProtocolRequirementDefinition
            let isStatic = !requirement.flags.isInstance
            if let variable = node.first(of: .variable), let name = variable.identifier, node.contains(.getter), let variableKinds = defaultImplementationVariableKindsByName[name] {
                requirementDefinition = .variable(VariableDefinition(node: node, name: name, hasSetter: variableKinds.contains(.setter), hasModifyAccessor: variableKinds.contains(.modifyAccessor), isGlobalOrStatic: isStatic, isStored: false))
            } else if let `subscript` = node.first(of: .subscript), let kinds = defaultImplementationSubscriptKindsByName[`subscript`] {
                requirementDefinition = .subscript(SubscriptDefinition(node: node, hasSetter: kinds.contains(.setter), hasReadAccessor: kinds.contains(.readAccessor), hasModifyAccessor: kinds.contains(.modifyAccessor), isStatic: isStatic))
            } else if node.contains(.allocator) {
                requirementDefinition = .function(FunctionDefinition(node: node, name: "", kind: .allocator, isGlobalOrStatic: true))
            } else if let function = node.first(of: .function), let name = function.identifier {
                requirementDefinition = .function(FunctionDefinition(node: node, name: name, kind: .function, isGlobalOrStatic: isStatic))
            } else {
                continue
            }
            defaultImplementationRequirements.append(requirementDefinition)
        }

        self.defaultImplementationRequirements = defaultImplementationRequirements

        var extensionDefinition = try ExtensionDefinition(name: name, kind: .protocol, genericSignature: nil, protocolConformance: nil, associatedType: nil, in: machO)

        for defaultImplementationRequirement in defaultImplementationRequirements {
            switch defaultImplementationRequirement {
            case .subscript(let subscriptDefinition):
                if subscriptDefinition.isStatic {
                    extensionDefinition.staticSubscripts.append(subscriptDefinition)
                } else {
                    extensionDefinition.subscripts.append(subscriptDefinition)
                }
            case .variable(let variableDefinition):
                if variableDefinition.isGlobalOrStatic {
                    extensionDefinition.staticVariables.append(variableDefinition)
                } else {
                    extensionDefinition.variables.append(variableDefinition)
                }
            case .function(let functionDefinition):
                switch functionDefinition.kind {
                case .function:
                    if functionDefinition.isGlobalOrStatic {
                        extensionDefinition.staticFunctions.append(functionDefinition)
                    } else {
                        extensionDefinition.functions.append(functionDefinition)
                    }
                case .allocator:
                    extensionDefinition.allocators.append(functionDefinition)
                case .constructor:
                    extensionDefinition.constructors.append(functionDefinition)
                }
            }
        }

        if extensionDefinition.hasMembers {
            self.defaultImplementationExtensions = [extensionDefinition]
        }
    }
}
