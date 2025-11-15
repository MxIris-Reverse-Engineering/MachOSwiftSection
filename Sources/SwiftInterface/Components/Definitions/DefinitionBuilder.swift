import Demangling
import MachOSymbols
import MachOSwiftSection

enum DefinitionBuilder {
    static func variables(for demangledSymbols: [DemangledSymbolWithOffset], fieldNames: borrowing Set<String> = [], methodDescriptorLookup: [Node: MethodDescriptorWrapper] = [:], isGlobalOrStatic: Bool) -> [VariableDefinition] {
        var variables: [VariableDefinition] = []
        var accessorsByName: [String: [Accessor]] = [:]
        for demangledSymbol in demangledSymbols {
            guard let variableNode = demangledSymbol.base.demangledNode.first(of: .variable) else { continue }
            guard let name = variableNode.identifier else { continue }
            let kind = demangledSymbol.accessorKind
            accessorsByName[name, default: []].append(.init(kind: kind, symbol: demangledSymbol.base, methodDescriptor: methodDescriptorLookup[demangledSymbol.demangledNode], offset: demangledSymbol.offset))
        }

        for (name, accessors) in accessorsByName {
            guard !fieldNames.contains(name) else { continue }
            let nodes = accessors.map(\.symbol.demangledNode)
            guard let node = nodes.first(where: { $0.contains(.getter) || !$0.hasAccessor }) else { continue }
            variables.append(.init(node: node, name: name, accessors: accessors, isGlobalOrStatic: isGlobalOrStatic))
        }
        return variables
    }

    static func subscripts(for demangledSymbols: [DemangledSymbolWithOffset], methodDescriptorLookup: [Node: MethodDescriptorWrapper] = [:], isStatic: Bool) -> [SubscriptDefinition] {
        var subscripts: [SubscriptDefinition] = []
        var accessorsByNode: [Node: [Accessor]] = [:]
        for demangledSymbol in demangledSymbols {
            guard let subscriptNode = demangledSymbol.demangledNode.first(of: .subscript) else { continue }
            let kind = demangledSymbol.accessorKind
            accessorsByNode[subscriptNode, default: []].append(.init(kind: kind, symbol: demangledSymbol.base, methodDescriptor: methodDescriptorLookup[demangledSymbol.demangledNode], offset: demangledSymbol.offset))
        }

        for (_, accessors) in accessorsByNode {
            let nodes = accessors.map(\.symbol.demangledNode)
            guard let node = nodes.first(where: { $0.contains(.getter) }) else { continue }
            subscripts.append(.init(node: node, accessors: accessors, isStatic: isStatic))
        }
        return subscripts
    }

    static func allocators(for demangledSymbols: [DemangledSymbolWithOffset], methodDescriptorLookup: [Node: MethodDescriptorWrapper] = [:]) -> [FunctionDefinition] {
        var allocators: [FunctionDefinition] = []
        for demangledSymbol in demangledSymbols {
            allocators.append(.init(node: demangledSymbol.demangledNode, name: "", kind: .allocator, symbol: demangledSymbol.base, isGlobalOrStatic: true, methodDescriptor: methodDescriptorLookup[demangledSymbol.demangledNode], offset: demangledSymbol.offset))
        }
        return allocators
    }

    static func functions(for demangledSymbols: [DemangledSymbolWithOffset], methodDescriptorLookup: [Node: MethodDescriptorWrapper] = [:], isGlobalOrStatic: Bool) -> [FunctionDefinition] {
        var functions: [FunctionDefinition] = []
        for demangledSymbol in demangledSymbols {
            guard let functionNode = demangledSymbol.demangledNode.first(of: .function), let name = functionNode.identifier else { continue }
            functions.append(.init(node: demangledSymbol.demangledNode, name: name, kind: .function, symbol: demangledSymbol.base, isGlobalOrStatic: isGlobalOrStatic, methodDescriptor: methodDescriptorLookup[demangledSymbol.demangledNode], offset: demangledSymbol.offset))
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
