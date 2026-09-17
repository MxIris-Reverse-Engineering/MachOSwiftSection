import Demangling
@_spi(Internals) import MachOSymbols
import MachOSwiftSection
import OrderedCollections

package enum DefinitionBuilder {
    /// The output of `variablesProduct(...)`: the computed-variable definitions
    /// plus the accessor groups that were suppressed because their name matches
    /// a stored field record (the property renders once, from the field
    /// descriptor, not from the accessor symbols). The suppressed groups carry
    /// the resolved method descriptors / vtable slots, so the caller can fold
    /// the dispatch facts (`final`, vtable comments, the lazy getter's
    /// caller-facing type) onto the matching `FieldDefinition` instead of
    /// discarding them.
    package struct VariablesBuildProduct {
        package let variables: [VariableDefinition]
        package let storedPropertyAccessorsByFieldName: [String: [Accessor]]
    }

    package static func variables(
        for memberSymbols: [MemberSymbol],
        fieldNames: borrowing Set<String> = [],
        dispatchLookups: ClassDispatchLookups = .init(),
        isGlobalOrStatic: Bool
    ) -> [VariableDefinition] {
        variablesProduct(
            for: memberSymbols,
            fieldNames: fieldNames,
            dispatchLookups: dispatchLookups,
            isGlobalOrStatic: isGlobalOrStatic
        ).variables
    }

    package static func variablesProduct(
        for memberSymbols: [MemberSymbol],
        fieldNames: borrowing Set<String> = [],
        dispatchLookups: ClassDispatchLookups = .init(),
        isGlobalOrStatic: Bool
    ) -> VariablesBuildProduct {
        var variables: [VariableDefinition] = []
        var accessorsByName: [String: [Accessor]] = [:]
        for memberSymbol in memberSymbols {
            guard let variableNode = memberSymbol.demangledNode.first(of: .variable) else { continue }
            guard let name = variableNode.identifier else { continue }
            let kind = memberSymbol.accessorKind
            let node = memberSymbol.demangledNode
            let symbolOffset = memberSymbol.offset
            let (descriptor, vtableOffset) = dispatchLookups.dispatch(forMemberNode: node, implementationOffset: symbolOffset)
            accessorsByName[name, default: []].append(.init(kind: kind, symbol: memberSymbol.base.detachedFromSharedTable(), methodDescriptor: descriptor, offset: memberSymbol.protocolWitnessTableOffset, vtableOffset: vtableOffset))
        }

        var storedPropertyAccessorsByFieldName: [String: [Accessor]] = [:]
        for (name, accessors) in accessorsByName.sorted(by: { $0.key < $1.key }) {
            guard !fieldNames.contains(name) else {
                storedPropertyAccessorsByFieldName[name] = accessors
                continue
            }
            let nodes = accessors.map(\.symbol.demangledNode)
            guard let node = nodes.first(where: { $0.contains(.getter) || !$0.hasAccessor }) else { continue }
            var variableDefinition = VariableDefinition(node: node, name: name, accessors: accessors, isGlobalOrStatic: isGlobalOrStatic)
            if accessors.contains(where: { $0.methodDescriptor?.method?.layout.flags.isDynamic ?? false }) {
                variableDefinition.attributes.append(.dynamic)
            }
            variables.append(variableDefinition)
        }
        return VariablesBuildProduct(variables: variables, storedPropertyAccessorsByFieldName: storedPropertyAccessorsByFieldName)
    }

    package static func subscripts(
        for memberSymbols: [MemberSymbol],
        dispatchLookups: ClassDispatchLookups = .init(),
        isStatic: Bool
    ) -> [SubscriptDefinition] {
        var subscripts: [SubscriptDefinition] = []
        // OrderedDictionary (not a plain `Dictionary`) so the emitted subscript
        // order is deterministic: overloaded subscripts all share the name
        // "subscript", so they cannot be name-sorted like `variables`; plain
        // `Dictionary` iteration order is randomized per process and made the
        // interface output unstable across runs. Insertion order follows the
        // (deterministic) symbol order of `memberSymbols`.
        //
        // Keyed structurally, not by bare `NodeReference`: these symbols do not
        // all come from one store (a resilient witness or protocol requirement
        // arrives through `SymbolicDemangler.demangleSymbolReference`, i.e. a mini
        // store), and store-identity keys would file a subscript's getter and
        // setter into two separate buckets — the setter-only bucket then loses
        // the `contains(.getter)` test below and the accessor disappears.
        var accessorsByNode: OrderedDictionary<StructuralNodeReferenceKey, [Accessor]> = [:]
        for memberSymbol in memberSymbols {
            guard let subscriptNode = memberSymbol.demangledNode.first(of: .subscript).map(StructuralNodeReferenceKey.init) else { continue }
            let kind = memberSymbol.accessorKind
            let node = memberSymbol.demangledNode
            let symbolOffset = memberSymbol.offset
            let (descriptor, vtableOffset) = dispatchLookups.dispatch(forMemberNode: node, implementationOffset: symbolOffset)
            accessorsByNode[subscriptNode, default: []].append(.init(kind: kind, symbol: memberSymbol.base.detachedFromSharedTable(), methodDescriptor: descriptor, offset: memberSymbol.protocolWitnessTableOffset, vtableOffset: vtableOffset))
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
        for memberSymbols: [MemberSymbol],
        dispatchLookups: ClassDispatchLookups = .init()
    ) -> [FunctionDefinition] {
        // Same dedup pattern as `functions(...)`: a merged-function thunk shares
        // the canonical `allocator` subtree, so the same init appears twice. Keep
        // the canonical (non-merged) entry when both are present. Structural keys
        // for the same reason as `subscripts(...)`: the thunk and its canonical
        // symbol need not have been demangled into the same store.
        var canonicalIndexByAllocatorNode: [StructuralNodeReferenceKey: Int] = [:]
        // OrderedDictionary so the merged-thunk tail is appended in deterministic
        // (symbol) order — plain `Dictionary` iteration is randomized per process.
        var pendingMergedByAllocatorNode: OrderedDictionary<StructuralNodeReferenceKey, MemberSymbol> = [:]
        var allocators: [FunctionDefinition] = []
        for memberSymbol in memberSymbols {
            guard let allocatorNode = memberSymbol.demangledNode.first(of: .allocator).map(StructuralNodeReferenceKey.init) else { continue }
            let isMergedThunk = memberSymbol.demangledNode.children.first?.kind == .mergedFunction
            if isMergedThunk {
                if canonicalIndexByAllocatorNode[allocatorNode] == nil, pendingMergedByAllocatorNode[allocatorNode] == nil {
                    pendingMergedByAllocatorNode[allocatorNode] = memberSymbol
                }
                continue
            }
            if canonicalIndexByAllocatorNode[allocatorNode] != nil { continue }
            canonicalIndexByAllocatorNode[allocatorNode] = allocators.count
            allocators.append(makeAllocatorDefinition(from: memberSymbol, dispatchLookups: dispatchLookups))
        }
        for (allocatorNode, mergedSymbol) in pendingMergedByAllocatorNode where canonicalIndexByAllocatorNode[allocatorNode] == nil {
            allocators.append(makeAllocatorDefinition(from: mergedSymbol, dispatchLookups: dispatchLookups))
        }
        return allocators
    }

    private static func makeAllocatorDefinition(
        from memberSymbol: MemberSymbol,
        dispatchLookups: ClassDispatchLookups
    ) -> FunctionDefinition {
        let node = memberSymbol.demangledNode
        let symbolOffset = memberSymbol.offset
        let (descriptor, vtableOffset) = dispatchLookups.dispatch(forMemberNode: node, implementationOffset: symbolOffset)
        var functionDefinition = FunctionDefinition(node: node, name: "", kind: .allocator, symbol: memberSymbol.base.detachedFromSharedTable(), isGlobalOrStatic: true, methodDescriptor: descriptor, offset: memberSymbol.protocolWitnessTableOffset, vtableOffset: vtableOffset)
        if let methodDescriptor = descriptor?.method, methodDescriptor.layout.flags.isDynamic {
            functionDefinition.attributes.append(.dynamic)
        }
        return functionDefinition
    }

    package static func functions(
        for memberSymbols: [MemberSymbol],
        dispatchLookups: ClassDispatchLookups = .init(),
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
        var pendingMergedByFunctionNode: OrderedDictionary<StructuralNodeReferenceKey, MemberSymbol> = [:]
        var functions: [FunctionDefinition] = []
        for memberSymbol in memberSymbols {
            guard let functionNode = memberSymbol.demangledNode.first(of: .function).map(StructuralNodeReferenceKey.init), let name = functionNode.reference.identifier else { continue }
            let isMergedThunk = memberSymbol.demangledNode.children.first?.kind == .mergedFunction
            if isMergedThunk {
                if canonicalIndexByFunctionNode[functionNode] == nil, pendingMergedByFunctionNode[functionNode] == nil {
                    pendingMergedByFunctionNode[functionNode] = memberSymbol
                }
                continue
            }
            if canonicalIndexByFunctionNode[functionNode] != nil { continue }
            canonicalIndexByFunctionNode[functionNode] = functions.count
            functions.append(makeFunctionDefinition(from: memberSymbol, name: name, isGlobalOrStatic: isGlobalOrStatic, dispatchLookups: dispatchLookups))
        }
        for (functionNode, mergedSymbol) in pendingMergedByFunctionNode where canonicalIndexByFunctionNode[functionNode] == nil {
            guard let name = functionNode.reference.identifier else { continue }
            functions.append(makeFunctionDefinition(from: mergedSymbol, name: name, isGlobalOrStatic: isGlobalOrStatic, dispatchLookups: dispatchLookups))
        }
        return functions
    }

    private static func makeFunctionDefinition(
        from memberSymbol: MemberSymbol,
        name: String,
        isGlobalOrStatic: Bool,
        dispatchLookups: ClassDispatchLookups
    ) -> FunctionDefinition {
        let node = memberSymbol.demangledNode
        let symbolOffset = memberSymbol.offset
        let (descriptor, vtableOffset) = dispatchLookups.dispatch(forMemberNode: node, implementationOffset: symbolOffset)
        var functionDefinition = FunctionDefinition(node: node, name: name, kind: .function, symbol: memberSymbol.base.detachedFromSharedTable(), isGlobalOrStatic: isGlobalOrStatic, methodDescriptor: descriptor, offset: memberSymbol.protocolWitnessTableOffset, vtableOffset: vtableOffset)
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
