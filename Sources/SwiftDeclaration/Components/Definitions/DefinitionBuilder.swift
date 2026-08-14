import Demangling
@_spi(Internals) import MachOSymbols
import MachOSwiftSection
import OrderedCollections

package enum DefinitionBuilder {
    package static func variables(
        for demangledSymbols: [DemangledSymbolWithOffset],
        fieldNames: borrowing Set<String> = [],
        methodDescriptorLookup: [StructuralNodeReferenceKey: MethodDescriptorWrapper] = [:],
        vtableOffsetLookup: [StructuralNodeReferenceKey: Int] = [:],
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
            let descriptor = methodDescriptorLookup[StructuralNodeReferenceKey(node)] ?? implOffsetDescriptorLookup[symbolOffset]
            let vtableOffset = vtableOffsetLookup[StructuralNodeReferenceKey(node)] ?? implOffsetVTableSlotLookup[symbolOffset]
            accessorsByName[name, default: []].append(.init(kind: kind, symbol: demangledSymbol.base.detachedFromSharedTable(), methodDescriptor: descriptor, offset: demangledSymbol.offset, vtableOffset: vtableOffset))
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

    package static func subscripts(
        for demangledSymbols: [DemangledSymbolWithOffset],
        methodDescriptorLookup: [StructuralNodeReferenceKey: MethodDescriptorWrapper] = [:],
        vtableOffsetLookup: [StructuralNodeReferenceKey: Int] = [:],
        implOffsetDescriptorLookup: [Int: MethodDescriptorWrapper] = [:],
        implOffsetVTableSlotLookup: [Int: Int] = [:],
        isStatic: Bool
    ) -> [SubscriptDefinition] {
        var subscripts: [SubscriptDefinition] = []
        // OrderedDictionary (not a plain `Dictionary`) so the emitted subscript
        // order is deterministic: overloaded subscripts all share the name
        // "subscript", so they cannot be name-sorted like `variables`; plain
        // `Dictionary` iteration order is randomized per process and made the
        // interface output unstable across runs. Insertion order follows the
        // (deterministic) symbol order of `demangledSymbols`.
        //
        // Keyed structurally, not by bare `NodeReference`: these symbols do not
        // all come from one store (a resilient witness or protocol requirement
        // arrives through `MetadataReader.demangleSymbolReference`, i.e. a mini
        // store), and store-identity keys would file a subscript's getter and
        // setter into two separate buckets — the setter-only bucket then loses
        // the `contains(.getter)` test below and the accessor disappears.
        var accessorsByNode: OrderedDictionary<StructuralNodeReferenceKey, [Accessor]> = [:]
        for demangledSymbol in demangledSymbols {
            guard let subscriptNode = demangledSymbol.demangledNode.first(of: .subscript).map(StructuralNodeReferenceKey.init) else { continue }
            let kind = demangledSymbol.accessorKind
            let node = demangledSymbol.demangledNode
            let symbolOffset = demangledSymbol.base.offset
            let descriptor = methodDescriptorLookup[StructuralNodeReferenceKey(node)] ?? implOffsetDescriptorLookup[symbolOffset]
            let vtableOffset = vtableOffsetLookup[StructuralNodeReferenceKey(node)] ?? implOffsetVTableSlotLookup[symbolOffset]
            accessorsByNode[subscriptNode, default: []].append(.init(kind: kind, symbol: demangledSymbol.base.detachedFromSharedTable(), methodDescriptor: descriptor, offset: demangledSymbol.offset, vtableOffset: vtableOffset))
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

    package static func allocators(
        for demangledSymbols: [DemangledSymbolWithOffset],
        methodDescriptorLookup: [StructuralNodeReferenceKey: MethodDescriptorWrapper] = [:],
        vtableOffsetLookup: [StructuralNodeReferenceKey: Int] = [:],
        implOffsetDescriptorLookup: [Int: MethodDescriptorWrapper] = [:],
        implOffsetVTableSlotLookup: [Int: Int] = [:]
    ) -> [FunctionDefinition] {
        // Same dedup pattern as `functions(...)`: a merged-function thunk shares
        // the canonical `allocator` subtree, so the same init appears twice. Keep
        // the canonical (non-merged) entry when both are present. Structural keys
        // for the same reason as `subscripts(...)`: the thunk and its canonical
        // symbol need not have been demangled into the same store.
        var canonicalIndexByAllocatorNode: [StructuralNodeReferenceKey: Int] = [:]
        // OrderedDictionary so the merged-thunk tail is appended in deterministic
        // (symbol) order — plain `Dictionary` iteration is randomized per process.
        var pendingMergedByAllocatorNode: OrderedDictionary<StructuralNodeReferenceKey, DemangledSymbolWithOffset> = [:]
        var allocators: [FunctionDefinition] = []
        for demangledSymbol in demangledSymbols {
            guard let allocatorNode = demangledSymbol.demangledNode.first(of: .allocator).map(StructuralNodeReferenceKey.init) else { continue }
            let isMergedThunk = demangledSymbol.base.demangledNode.children.first?.kind == .mergedFunction
            if isMergedThunk {
                if canonicalIndexByAllocatorNode[allocatorNode] == nil, pendingMergedByAllocatorNode[allocatorNode] == nil {
                    pendingMergedByAllocatorNode[allocatorNode] = demangledSymbol
                }
                continue
            }
            if canonicalIndexByAllocatorNode[allocatorNode] != nil { continue }
            canonicalIndexByAllocatorNode[allocatorNode] = allocators.count
            allocators.append(makeAllocatorDefinition(from: demangledSymbol, methodDescriptorLookup: methodDescriptorLookup, vtableOffsetLookup: vtableOffsetLookup, implOffsetDescriptorLookup: implOffsetDescriptorLookup, implOffsetVTableSlotLookup: implOffsetVTableSlotLookup))
        }
        for (allocatorNode, mergedSymbol) in pendingMergedByAllocatorNode where canonicalIndexByAllocatorNode[allocatorNode] == nil {
            allocators.append(makeAllocatorDefinition(from: mergedSymbol, methodDescriptorLookup: methodDescriptorLookup, vtableOffsetLookup: vtableOffsetLookup, implOffsetDescriptorLookup: implOffsetDescriptorLookup, implOffsetVTableSlotLookup: implOffsetVTableSlotLookup))
        }
        return allocators
    }

    private static func makeAllocatorDefinition(
        from demangledSymbol: DemangledSymbolWithOffset,
        methodDescriptorLookup: [StructuralNodeReferenceKey: MethodDescriptorWrapper],
        vtableOffsetLookup: [StructuralNodeReferenceKey: Int],
        implOffsetDescriptorLookup: [Int: MethodDescriptorWrapper],
        implOffsetVTableSlotLookup: [Int: Int]
    ) -> FunctionDefinition {
        let node = demangledSymbol.demangledNode
        let symbolOffset = demangledSymbol.base.offset
        let descriptor = methodDescriptorLookup[StructuralNodeReferenceKey(node)] ?? implOffsetDescriptorLookup[symbolOffset]
        let vtableOffset = vtableOffsetLookup[StructuralNodeReferenceKey(node)] ?? implOffsetVTableSlotLookup[symbolOffset]
        var functionDefinition = FunctionDefinition(node: node, name: "", kind: .allocator, symbol: demangledSymbol.base.detachedFromSharedTable(), isGlobalOrStatic: true, methodDescriptor: descriptor, offset: demangledSymbol.offset, vtableOffset: vtableOffset)
        if let methodDescriptor = descriptor?.method, methodDescriptor.layout.flags.isDynamic {
            functionDefinition.attributes.append(.dynamic)
        }
        return functionDefinition
    }

    package static func functions(
        for demangledSymbols: [DemangledSymbolWithOffset],
        methodDescriptorLookup: [StructuralNodeReferenceKey: MethodDescriptorWrapper] = [:],
        vtableOffsetLookup: [StructuralNodeReferenceKey: Int] = [:],
        implOffsetDescriptorLookup: [Int: MethodDescriptorWrapper] = [:],
        implOffsetVTableSlotLookup: [Int: Int] = [:],
        isGlobalOrStatic: Bool
    ) -> [FunctionDefinition] {
        // Dedup pass: merged-function thunks (`.mergedFunction` root) share the
        // same inner `function` subtree as the canonical function symbol. Without
        // deduping, the same source-level declaration appears twice. Prefer the
        // canonical (non-merged) symbol when both exist; fall back to the merged
        // one when it's the only copy.
        // Structural keys for the same reason as `subscripts(...)`: the thunk and
        // its canonical symbol need not have been demangled into the same store.
        var canonicalIndexByFunctionNode: [StructuralNodeReferenceKey: Int] = [:]
        // OrderedDictionary so the merged-thunk tail is appended in deterministic
        // (symbol) order — plain `Dictionary` iteration is randomized per process.
        var pendingMergedByFunctionNode: OrderedDictionary<StructuralNodeReferenceKey, DemangledSymbolWithOffset> = [:]
        var functions: [FunctionDefinition] = []
        for demangledSymbol in demangledSymbols {
            guard let functionNode = demangledSymbol.demangledNode.first(of: .function).map(StructuralNodeReferenceKey.init), let name = functionNode.reference.identifier else { continue }
            let isMergedThunk = demangledSymbol.base.demangledNode.children.first?.kind == .mergedFunction
            if isMergedThunk {
                if canonicalIndexByFunctionNode[functionNode] == nil, pendingMergedByFunctionNode[functionNode] == nil {
                    pendingMergedByFunctionNode[functionNode] = demangledSymbol
                }
                continue
            }
            if canonicalIndexByFunctionNode[functionNode] != nil { continue }
            canonicalIndexByFunctionNode[functionNode] = functions.count
            functions.append(makeFunctionDefinition(from: demangledSymbol, name: name, isGlobalOrStatic: isGlobalOrStatic, methodDescriptorLookup: methodDescriptorLookup, vtableOffsetLookup: vtableOffsetLookup, implOffsetDescriptorLookup: implOffsetDescriptorLookup, implOffsetVTableSlotLookup: implOffsetVTableSlotLookup))
        }
        for (functionNode, mergedSymbol) in pendingMergedByFunctionNode where canonicalIndexByFunctionNode[functionNode] == nil {
            guard let name = functionNode.reference.identifier else { continue }
            functions.append(makeFunctionDefinition(from: mergedSymbol, name: name, isGlobalOrStatic: isGlobalOrStatic, methodDescriptorLookup: methodDescriptorLookup, vtableOffsetLookup: vtableOffsetLookup, implOffsetDescriptorLookup: implOffsetDescriptorLookup, implOffsetVTableSlotLookup: implOffsetVTableSlotLookup))
        }
        return functions
    }

    private static func makeFunctionDefinition(
        from demangledSymbol: DemangledSymbolWithOffset,
        name: String,
        isGlobalOrStatic: Bool,
        methodDescriptorLookup: [StructuralNodeReferenceKey: MethodDescriptorWrapper],
        vtableOffsetLookup: [StructuralNodeReferenceKey: Int],
        implOffsetDescriptorLookup: [Int: MethodDescriptorWrapper],
        implOffsetVTableSlotLookup: [Int: Int]
    ) -> FunctionDefinition {
        let node = demangledSymbol.demangledNode
        let symbolOffset = demangledSymbol.base.offset
        let descriptor = methodDescriptorLookup[StructuralNodeReferenceKey(node)] ?? implOffsetDescriptorLookup[symbolOffset]
        let vtableOffset = vtableOffsetLookup[StructuralNodeReferenceKey(node)] ?? implOffsetVTableSlotLookup[symbolOffset]
        var functionDefinition = FunctionDefinition(node: node, name: name, kind: .function, symbol: demangledSymbol.base.detachedFromSharedTable(), isGlobalOrStatic: isGlobalOrStatic, methodDescriptor: descriptor, offset: demangledSymbol.offset, vtableOffset: vtableOffset)
        if let methodDescriptor = descriptor?.method, methodDescriptor.layout.flags.isDynamic {
            functionDefinition.attributes.append(.dynamic)
        }
        return functionDefinition
    }
}

extension DemanglingNode where Self: Sequence<Self> {
    var isStoredVariable: Bool {
        guard first(of: .variable) != nil else { return false }
        // A stored variable is one not wrapped in an accessor (getter/setter/etc.)
        return !hasAccessor
    }
}
