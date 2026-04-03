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
            variables.append(.init(node: node, name: name, accessors: accessors, isGlobalOrStatic: isGlobalOrStatic))
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
            subscripts.append(.init(node: node, accessors: accessors, isStatic: isStatic))
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
