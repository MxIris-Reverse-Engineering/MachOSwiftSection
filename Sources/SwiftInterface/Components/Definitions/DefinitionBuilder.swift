import Demangling
import MachOSymbols
import MachOSwiftSection
import SwiftDump

enum DefinitionBuilder {
    static func variables(
        for demangledSymbols: [DemangledSymbolWithOffset],
        fieldNames: borrowing Set<String> = [],
        methodDescriptorLookup: [Node: MethodDescriptorWrapper] = [:],
        vtableOffsetLookup: [Node: Int] = [:],
        implOffsetDescriptorLookup: [Int: MethodDescriptorWrapper] = [:],
        implOffsetVTableSlotLookup: [Int: Int] = [:],
        isGlobalOrStatic: Bool
    ) -> [VariableDefinition] {
        var variables: [VariableDefinition] = []
        var accessorsByName: [String: [Accessor]] = [:]
        for demangledSymbol in demangledSymbols {
            guard let variableNode = demangledSymbol.base.demangledNode.first(of: .variable) else { continue }
            guard let name = variableNode.identifier else { continue }
            let kind = demangledSymbol.accessorKind
            let node = demangledSymbol.demangledNode
            let symbolOffset = demangledSymbol.base.offset
            let descriptor = methodDescriptorLookup[node] ?? implOffsetDescriptorLookup[symbolOffset]
            let vtableOffset = vtableOffsetLookup[node] ?? implOffsetVTableSlotLookup[symbolOffset]
            accessorsByName[name, default: []].append(.init(kind: kind, symbol: demangledSymbol.base, methodDescriptor: descriptor, offset: demangledSymbol.offset, vtableOffset: vtableOffset))
        }

        for (name, accessors) in accessorsByName.sorted(by: { $0.key < $1.key }) {
            guard !fieldNames.contains(name) else { continue }
            let nodes = accessors.map(\.symbol.demangledNode)
            guard let node = nodes.first(where: { $0.contains(.getter) || !$0.hasAccessor }) else { continue }
            var variableDefinition = VariableDefinition(node: node, name: name, accessors: accessors, isGlobalOrStatic: isGlobalOrStatic)
            if accessors.contains(where: { $0.methodDescriptor?.method?.layout.flags.isDynamic ?? false }) {
                variableDefinition.attributes.append(.dynamic)
            }
            variables.append(variableDefinition)
        }
        return variables
    }

    static func subscripts(
        for demangledSymbols: [DemangledSymbolWithOffset],
        methodDescriptorLookup: [Node: MethodDescriptorWrapper] = [:],
        vtableOffsetLookup: [Node: Int] = [:],
        implOffsetDescriptorLookup: [Int: MethodDescriptorWrapper] = [:],
        implOffsetVTableSlotLookup: [Int: Int] = [:],
        isStatic: Bool
    ) -> [SubscriptDefinition] {
        var subscripts: [SubscriptDefinition] = []
        var accessorsByNode: [Node: [Accessor]] = [:]
        for demangledSymbol in demangledSymbols {
            guard let subscriptNode = demangledSymbol.demangledNode.first(of: .subscript) else { continue }
            let kind = demangledSymbol.accessorKind
            let node = demangledSymbol.demangledNode
            let symbolOffset = demangledSymbol.base.offset
            let descriptor = methodDescriptorLookup[node] ?? implOffsetDescriptorLookup[symbolOffset]
            let vtableOffset = vtableOffsetLookup[node] ?? implOffsetVTableSlotLookup[symbolOffset]
            accessorsByNode[subscriptNode, default: []].append(.init(kind: kind, symbol: demangledSymbol.base, methodDescriptor: descriptor, offset: demangledSymbol.offset, vtableOffset: vtableOffset))
        }

        for (_, accessors) in accessorsByNode {
            let nodes = accessors.map(\.symbol.demangledNode)
            guard let node = nodes.first(where: { $0.contains(.getter) }) else { continue }
            var subscriptDefinition = SubscriptDefinition(node: node, accessors: accessors, isStatic: isStatic)
            if accessors.contains(where: { $0.methodDescriptor?.method?.layout.flags.isDynamic ?? false }) {
                subscriptDefinition.attributes.append(.dynamic)
            }
            subscripts.append(subscriptDefinition)
        }
        return subscripts
    }

    static func allocators(
        for demangledSymbols: [DemangledSymbolWithOffset],
        methodDescriptorLookup: [Node: MethodDescriptorWrapper] = [:],
        vtableOffsetLookup: [Node: Int] = [:],
        implOffsetDescriptorLookup: [Int: MethodDescriptorWrapper] = [:],
        implOffsetVTableSlotLookup: [Int: Int] = [:]
    ) -> [FunctionDefinition] {
        var allocators: [FunctionDefinition] = []
        for demangledSymbol in demangledSymbols {
            let node = demangledSymbol.demangledNode
            let symbolOffset = demangledSymbol.base.offset
            let descriptor = methodDescriptorLookup[node] ?? implOffsetDescriptorLookup[symbolOffset]
            let vtableOffset = vtableOffsetLookup[node] ?? implOffsetVTableSlotLookup[symbolOffset]
            var functionDefinition = FunctionDefinition(node: node, name: "", kind: .allocator, symbol: demangledSymbol.base, isGlobalOrStatic: true, methodDescriptor: descriptor, offset: demangledSymbol.offset, vtableOffset: vtableOffset)
            if let methodDescriptor = descriptor?.method, methodDescriptor.layout.flags.isDynamic {
                functionDefinition.attributes.append(.dynamic)
            }
            allocators.append(functionDefinition)
        }
        return allocators
    }

    static func functions(
        for demangledSymbols: [DemangledSymbolWithOffset],
        methodDescriptorLookup: [Node: MethodDescriptorWrapper] = [:],
        vtableOffsetLookup: [Node: Int] = [:],
        implOffsetDescriptorLookup: [Int: MethodDescriptorWrapper] = [:],
        implOffsetVTableSlotLookup: [Int: Int] = [:],
        isGlobalOrStatic: Bool
    ) -> [FunctionDefinition] {
        var functions: [FunctionDefinition] = []
        for demangledSymbol in demangledSymbols {
            guard let functionNode = demangledSymbol.demangledNode.first(of: .function), let name = functionNode.identifier else { continue }
            let node = demangledSymbol.demangledNode
            let symbolOffset = demangledSymbol.base.offset
            let descriptor = methodDescriptorLookup[node] ?? implOffsetDescriptorLookup[symbolOffset]
            let vtableOffset = vtableOffsetLookup[node] ?? implOffsetVTableSlotLookup[symbolOffset]
            var functionDefinition = FunctionDefinition(node: node, name: name, kind: .function, symbol: demangledSymbol.base, isGlobalOrStatic: isGlobalOrStatic, methodDescriptor: descriptor, offset: demangledSymbol.offset, vtableOffset: vtableOffset)
            if let methodDescriptor = descriptor?.method, methodDescriptor.layout.flags.isDynamic {
                functionDefinition.attributes.append(.dynamic)
            }
            functions.append(functionDefinition)
        }
        return functions
    }
}

extension Node {
    var isStoredVariable: Bool {
        guard first(of: .variable) != nil else { return false }
        // A stored variable is one not wrapped in an accessor (getter/setter/etc.)
        return !hasAccessor
    }
}
