/// Factory for creating and interning Node instances.
///
/// Provides two optimization strategies:
/// 1. **Static singletons**: Pre-created instances for parameterless nodes (e.g., `.emptyList`)
/// 2. **Post-processing interning**: Deduplicate entire node trees after parsing
///
/// These optimizations can significantly reduce memory usage when parsing large binaries
/// like SwiftUI (4M+ nodes).
public enum NodeFactory {
    
    // MARK: - Static Singletons (Parameterless Nodes)
    
    // These are the most common parameterless nodes found in Demangler.
    // Using static constants ensures only one instance exists per kind.
    
    /// `.emptyList` - extremely common in function signatures
    public static let emptyList = Node(kind: .emptyList)
    
    /// `.firstElementMarker` - used in tuple/label processing
    public static let firstElementMarker = Node(kind: .firstElementMarker)
    
    /// `.labelList` - used in function parameter labels
    public static let labelList = Node(kind: .labelList)
    
    /// `.throwsAnnotation` - function throws marker
    public static let throwsAnnotation = Node(kind: .throwsAnnotation)
    
    /// `.asyncAnnotation` - async function marker
    public static let asyncAnnotation = Node(kind: .asyncAnnotation)
    
    /// `.variadicMarker` - variadic parameter marker
    public static let variadicMarker = Node(kind: .variadicMarker)
    
    /// `.concurrentFunctionType` - @Sendable function marker
    public static let concurrentFunctionType = Node(kind: .concurrentFunctionType)
    
    /// `.isolatedAnyFunctionType` - @isolated(any) marker
    public static let isolatedAnyFunctionType = Node(kind: .isolatedAnyFunctionType)
    
    /// `.nonIsolatedCallerFunctionType` - nonisolated(unsafe) marker
    public static let nonIsolatedCallerFunctionType = Node(kind: .nonIsolatedCallerFunctionType)
    
    /// `.sendingResultFunctionType` - sending result marker
    public static let sendingResultFunctionType = Node(kind: .sendingResultFunctionType)
    
    /// `.unknownIndex` - placeholder for unknown indices
    public static let unknownIndex = Node(kind: .unknownIndex)
    
    /// `.constrainedExistentialSelf` - Self in constrained existential
    public static let constrainedExistentialSelf = Node(kind: .constrainedExistentialSelf)
    
    // Function attributes
    public static let objCAttribute = Node(kind: .objCAttribute)
    public static let nonObjCAttribute = Node(kind: .nonObjCAttribute)
    public static let dynamicAttribute = Node(kind: .dynamicAttribute)
    public static let directMethodReferenceAttribute = Node(kind: .directMethodReferenceAttribute)
    public static let distributedThunk = Node(kind: .distributedThunk)
    public static let distributedAccessor = Node(kind: .distributedAccessor)
    public static let partialApplyObjCForwarder = Node(kind: .partialApplyObjCForwarder)
    public static let partialApplyForwarder = Node(kind: .partialApplyForwarder)
    public static let mergedFunction = Node(kind: .mergedFunction)
    public static let dynamicallyReplaceableFunctionVar = Node(kind: .dynamicallyReplaceableFunctionVar)
    public static let dynamicallyReplaceableFunctionKey = Node(kind: .dynamicallyReplaceableFunctionKey)
    public static let dynamicallyReplaceableFunctionImpl = Node(kind: .dynamicallyReplaceableFunctionImpl)
    
    // Async/thunk related
    public static let asyncFunctionPointer = Node(kind: .asyncFunctionPointer)
    public static let backDeploymentThunk = Node(kind: .backDeploymentThunk)
    public static let backDeploymentFallback = Node(kind: .backDeploymentFallback)
    public static let coroFunctionPointer = Node(kind: .coroFunctionPointer)
    public static let defaultOverride = Node(kind: .defaultOverride)
    public static let hasSymbolQuery = Node(kind: .hasSymbolQuery)
    public static let accessibleFunctionRecord = Node(kind: .accessibleFunctionRecord)
    
    // Impl function markers
    public static let implEscaping = Node(kind: .implEscaping)
    public static let implErasedIsolation = Node(kind: .implErasedIsolation)
    public static let implSendingResult = Node(kind: .implSendingResult)
    
    // Serialization/async markers
    public static let isSerialized = Node(kind: .isSerialized)
    public static let asyncRemoved = Node(kind: .asyncRemoved)
    
    // Common type nodes
    public static let tuple = Node(kind: .tuple)
    public static let pack = Node(kind: .pack)
    public static let errorType = Node(kind: .errorType)
    public static let sugaredOptional = Node(kind: .sugaredOptional)
    public static let sugaredArray = Node(kind: .sugaredArray)
    public static let sugaredParen = Node(kind: .sugaredParen)
    public static let opaqueReturnType = Node(kind: .opaqueReturnType)
    public static let vTableAttribute = Node(kind: .vTableAttribute)
}

// MARK: - Node Interning

extension Node {
    /// Recursively interns this node tree, returning deduplicated nodes.
    ///
    /// This is a post-processing optimization that should be called after
    /// demangling is complete. It traverses the tree bottom-up, ensuring
    /// identical subtrees share the same Node instance.
    ///
    /// - Parameter cache: A dictionary to store interned nodes. Pass the same
    ///   cache across multiple `intern` calls to maximize deduplication.
    /// - Returns: The interned node (may be self if already unique, or an
    ///   existing cached node if a duplicate was found).
    ///
    /// Example:
    /// ```swift
    /// var cache: [Node: Node] = [:]
    /// let internedRoot = demangledNode.interned(into: &cache)
    /// ```
    public func interned(into cache: inout [Node: Node]) -> Node {
        // First, intern all children recursively
        let internedChildren: [Node] = children.map { $0.interned(into: &cache) }
        
        // Check if any child was replaced (identity check)
        var childrenChanged = false
        if internedChildren.count == children.count {
            for (original, interned) in zip(children, internedChildren) {
                if original !== interned {
                    childrenChanged = true
                    break
                }
            }
        } else {
            childrenChanged = true
        }
        
        // Determine the canonical node
        let canonical: Node
        if childrenChanged {
            // Children changed, need to create a new node with interned children
            canonical = Node(kind: kind, contents: contents, children: internedChildren)
        } else {
            // Children unchanged, use self as canonical
            canonical = self
        }
        
        // Look up or insert into cache
        if let existing = cache[canonical] {
            return existing
        }
        cache[canonical] = canonical
        return canonical
    }
    
    /// Convenience method that creates a new cache and interns this tree.
    ///
    /// Use this when interning a single tree. For interning multiple trees
    /// (e.g., all symbols in a binary), use `interned(into:)` with a shared cache.
    public func interned() -> Node {
        var cache: [Node: Node] = [:]
        return interned(into: &cache)
    }
}

// MARK: - Batch Interning

extension NodeFactory {
    /// Interns multiple node trees, sharing a common cache for maximum deduplication.
    ///
    /// - Parameter nodes: An array of root nodes to intern.
    /// - Returns: A tuple containing:
    ///   - `nodes`: The interned nodes in the same order as input
    ///   - `cache`: The cache used, which can be reused for additional interning
    ///
    /// Example:
    /// ```swift
    /// let demangledSymbols: [Node] = symbols.map { try demangleAsNode($0) }
    /// let (interned, cache) = NodeFactory.intern(demangledSymbols)
    /// print("Reduced from \(countNodes(demangledSymbols)) to \(cache.count) unique nodes")
    /// ```
    public static func intern(_ nodes: [Node]) -> (nodes: [Node], cache: [Node: Node]) {
        var cache: [Node: Node] = [:]
        let interned = nodes.map { $0.interned(into: &cache) }
        return (interned, cache)
    }
    
    /// Interns multiple node trees into an existing cache.
    ///
    /// - Parameters:
    ///   - nodes: An array of root nodes to intern.
    ///   - cache: An existing cache to use and update.
    /// - Returns: The interned nodes in the same order as input.
    public static func intern(_ nodes: [Node], into cache: inout [Node: Node]) -> [Node] {
        return nodes.map { $0.interned(into: &cache) }
    }
}
