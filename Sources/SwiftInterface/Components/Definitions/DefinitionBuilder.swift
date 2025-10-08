import Demangle
import MachOSymbols

enum DefinitionBuilder {
    static func variables(for demangledSymbols: [DemangledSymbol], fieldNames: borrowing Set<String> = [], methodDescriptorLookup: [Node: MethodDescriptorWrapper] = [:], isGlobalOrStatic: Bool) -> [VariableDefinition] {
        var variables: [VariableDefinition] = []
        var accessorsByName: [String: [Accessor]] = [:]
        for demangledSymbol in demangledSymbols {
            guard let variableNode = demangledSymbol.demangledNode.first(of: .variable) else { continue }
            guard let name = variableNode.identifier else { continue }
            let kind = demangledSymbol.accessorKind
            accessorsByName[name, default: []].append(.init(kind: kind, symbol: demangledSymbol, methodDescriptor: methodDescriptorLookup[demangledSymbol.demangledNode]))
        }

        for (name, accessors) in accessorsByName {
            guard !fieldNames.contains(name) else { continue }
            let nodes = accessors.map(\.symbol.demangledNode)
            guard let node = nodes.first(where: { $0.contains(.getter) || !$0.hasAccessor }) else { continue }
            variables.append(.init(node: node, name: name, accessors: accessors, isGlobalOrStatic: isGlobalOrStatic))
        }
        return variables
    }

    static func subscripts(for demangledSymbols: [DemangledSymbol], methodDescriptorLookup: [Node: MethodDescriptorWrapper] = [:], isStatic: Bool) -> [SubscriptDefinition] {
        var subscripts: [SubscriptDefinition] = []
        var accessorsByNode: [Node: [Accessor]] = [:]
        for demangledSymbol in demangledSymbols {
            guard let subscriptNode = demangledSymbol.demangledNode.first(of: .subscript) else { continue }
            let kind = demangledSymbol.accessorKind
            accessorsByNode[subscriptNode, default: []].append(.init(kind: kind, symbol: demangledSymbol, methodDescriptor: methodDescriptorLookup[demangledSymbol.demangledNode]))
        }

        for (_, accessors) in accessorsByNode {
            let nodes = accessors.map(\.symbol.demangledNode)
            guard let node = nodes.first(where: { $0.contains(.getter) }) else { continue }
            subscripts.append(.init(node: node, accessors: accessors, isStatic: isStatic))
        }
        return subscripts
    }

    static func allocators(for demangledSymbols: [DemangledSymbol], methodDescriptorLookup: [Node: MethodDescriptorWrapper] = [:]) -> [FunctionDefinition] {
        var allocators: [FunctionDefinition] = []
        for demangledSymbol in demangledSymbols {
            allocators.append(.init(node: demangledSymbol.demangledNode, name: "", kind: .allocator, symbol: demangledSymbol, isGlobalOrStatic: true, methodDescriptor: methodDescriptorLookup[demangledSymbol.demangledNode]))
        }
        return allocators
    }

    static func functions(for demangledSymbols: [DemangledSymbol], methodDescriptorLookup: [Node: MethodDescriptorWrapper] = [:], isGlobalOrStatic: Bool) -> [FunctionDefinition] {
        var functions: [FunctionDefinition] = []
        for demangledSymbol in demangledSymbols {
            guard let functionNode = demangledSymbol.demangledNode.first(of: .function), let name = functionNode.identifier else { continue }
            functions.append(.init(node: demangledSymbol.demangledNode, name: name, kind: .function, symbol: demangledSymbol, isGlobalOrStatic: isGlobalOrStatic, methodDescriptor: methodDescriptorLookup[demangledSymbol.demangledNode]))
        }
        return functions
    }
}

extension Node {
    var isStoredVariable: Bool {
        guard let variableNode = first(of: .variable) else { return false }
        return variableNode.parent?.isAccessor == false
    }
}
