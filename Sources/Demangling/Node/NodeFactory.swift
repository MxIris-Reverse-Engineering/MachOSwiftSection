import Foundation

/// Global cache for interning Node instances.
///
/// This cache stores nodes by their structural identity (kind + contents + children),
/// allowing identical node structures to share the same instance in memory.
///
/// ## Thread Safety
/// The cache uses a lock for thread-safe access. For single-threaded scenarios
/// or when you control the threading, you can use the unsynchronized methods
/// for better performance.
///
/// ## Usage
///
/// ```swift
/// // Get or create an interned node
/// let node = NodeCache.shared.intern(kind: .identifier, text: "foo")
///
/// // Intern an existing node tree (post-processing)
/// let interned = NodeCache.shared.intern(existingNode)
///
/// // Clear cache when done processing a binary
/// NodeCache.shared.clear()
/// ```
public final class NodeCache: @unchecked Sendable {
    /// The shared global cache instance.
    public static let shared = NodeCache()
    
    /// Storage for interned nodes, keyed by their structural identity.
    private var storage: [Node: Node] = [:]
    
    /// Lock for thread-safe access.
    private let lock = NSLock()
    
    /// Number of unique nodes in the cache.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }
    
    /// Creates a new empty cache.
    /// Use this for isolated caching scenarios. For shared caching, use `NodeCache.shared`.
    public init() {}
    
    // MARK: - Leaf Node Interning (No Children)
    
    /// Interns a leaf node with no contents and no children.
    /// Returns an existing cached node if one exists, otherwise creates and caches a new one.
    public func intern(kind: Node.Kind) -> Node {
        let probe = Node(kind: kind)
        return internNode(probe)
    }
    
    /// Interns a leaf node with text contents.
    public func intern(kind: Node.Kind, text: String) -> Node {
        let probe = Node(kind: kind, text: text)
        return internNode(probe)
    }
    
    /// Interns a leaf node with index contents.
    public func intern(kind: Node.Kind, index: UInt64) -> Node {
        let probe = Node(kind: kind, index: index)
        return internNode(probe)
    }
    
    // MARK: - Node with Children Interning
    
    /// Interns a node with a single child.
    /// The child should already be interned for maximum deduplication.
    public func intern(kind: Node.Kind, child: Node) -> Node {
        let probe = Node(kind: kind, child: child)
        return internNode(probe)
    }
    
    /// Interns a node with multiple children.
    /// The children should already be interned for maximum deduplication.
    public func intern(kind: Node.Kind, children: [Node]) -> Node {
        let probe = Node(kind: kind, children: children)
        return internNode(probe)
    }
    
    /// Interns a node with text contents and children.
    public func intern(kind: Node.Kind, text: String, children: [Node]) -> Node {
        let probe = Node(kind: kind, text: text, children: children)
        return internNode(probe)
    }
    
    /// Interns a node with index contents and children.
    public func intern(kind: Node.Kind, index: UInt64, children: [Node]) -> Node {
        let probe = Node(kind: kind, index: index, children: children)
        return internNode(probe)
    }
    
    // MARK: - Tree Interning (Post-Processing)
    
    /// Recursively interns a node tree, returning deduplicated nodes.
    ///
    /// This traverses the tree bottom-up, ensuring identical subtrees
    /// share the same Node instance.
    ///
    /// - Parameter node: The root node to intern.
    /// - Returns: The interned node (may be the same instance if already cached,
    ///   or a cached instance if a duplicate was found).
    public func intern(_ node: Node) -> Node {
        lock.lock()
        defer { lock.unlock() }
        return internTreeUnsafe(node)
    }
    
    /// Recursively interns multiple node trees.
    public func intern(_ nodes: [Node]) -> [Node] {
        lock.lock()
        defer { lock.unlock() }
        return nodes.map { internTreeUnsafe($0) }
    }
    
    // MARK: - Unsynchronized Methods (for single-threaded use)
    
    /// Interns a node without locking. Use only in single-threaded contexts.
    public func internUnsafe(kind: Node.Kind) -> Node {
        let probe = Node(kind: kind)
        return internNodeUnsafe(probe)
    }
    
    /// Interns a node with text without locking.
    public func internUnsafe(kind: Node.Kind, text: String) -> Node {
        let probe = Node(kind: kind, text: text)
        return internNodeUnsafe(probe)
    }
    
    /// Interns a node with index without locking.
    public func internUnsafe(kind: Node.Kind, index: UInt64) -> Node {
        let probe = Node(kind: kind, index: index)
        return internNodeUnsafe(probe)
    }
    
    /// Interns a node with children without locking.
    public func internUnsafe(kind: Node.Kind, children: [Node]) -> Node {
        let probe = Node(kind: kind, children: children)
        return internNodeUnsafe(probe)
    }
    
    /// Recursively interns a node tree without locking.
    public func internTreeUnsafe(_ node: Node) -> Node {
        // First, intern all children recursively
        let internedChildren: [Node] = node.children.map { internTreeUnsafe($0) }
        
        // Check if any child was replaced (identity check)
        var childrenChanged = false
        if internedChildren.count == node.children.count {
            for (original, interned) in zip(node.children, internedChildren) {
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
            canonical = Node(kind: node.kind, contents: node.contents, children: internedChildren)
        } else {
            canonical = node
        }
        
        return internNodeUnsafe(canonical)
    }
    
    // MARK: - Cache Management
    
    /// Clears all cached nodes.
    /// Call this when you're done processing a binary to free memory.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
    
    /// Reserves capacity for the expected number of unique nodes.
    public func reserveCapacity(_ minimumCapacity: Int) {
        lock.lock()
        defer { lock.unlock() }
        storage.reserveCapacity(minimumCapacity)
    }
    
    // MARK: - Private Helpers
    
    private func internNode(_ node: Node) -> Node {
        lock.lock()
        defer { lock.unlock() }
        return internNodeUnsafe(node)
    }
    
    private func internNodeUnsafe(_ node: Node) -> Node {
        if let existing = storage[node] {
            return existing
        }
        storage[node] = node
        return node
    }
}

// MARK: - NodeFactory Static Singletons

/// Factory providing pre-created singleton instances for common parameterless nodes.
///
/// These singletons are used directly by `Demangler` during parsing to avoid
/// creating duplicate instances of frequently-used nodes.
///
/// For nodes with contents or children, use `NodeCache.shared` to intern them.
public enum NodeFactory {
    
    // MARK: - Static Singletons (Parameterless Nodes)
    
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

// MARK: - Node Interning Extension

extension Node {
    /// Interns this node tree into the global cache.
    ///
    /// Convenience method that calls `NodeCache.shared.intern(self)`.
    public func interned() -> Node {
        NodeCache.shared.intern(self)
    }
}

