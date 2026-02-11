import Foundation

/// Global cache for interning Node instances.
///
/// This cache stores nodes by their structural identity (kind + contents + children),
/// allowing identical node structures to share the same instance in memory.
///
/// ## Performance Optimization
/// This implementation avoids the O(n²) recursive hash problem by:
/// 1. Separating leaf nodes (no children) from tree nodes (with children)
/// 2. Using ObjectIdentifier-based hashing for tree nodes, which is O(1) per child
///    since children are already interned
/// 3. Using lightweight key structs instead of Node for dictionary lookup
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

    // MARK: - Key Types for O(1) Lookup

    /// Key for leaf nodes (no children). Uses kind + contents for identity.
    private struct LeafKey: Hashable {
        let kind: Node.Kind
        let contents: Node.Contents

        init(_ node: Node) {
            self.kind = node.kind
            self.contents = node.contents
        }

        init(kind: Node.Kind, contents: Node.Contents = .none) {
            self.kind = kind
            self.contents = contents
        }
    }

    /// Key for tree nodes (with children). Uses ObjectIdentifier for children
    /// since they are already interned, making hash computation O(n) where n
    /// is the number of direct children, not the entire subtree.
    private struct TreeKey: Hashable {
        let kind: Node.Kind
        let contents: Node.Contents
        let childCount: Int
        // Store ObjectIdentifiers of children for O(1) identity-based hashing
        let childIdentities: [ObjectIdentifier]
        // Precomputed hash for fast lookup
        let precomputedHash: Int

        init(_ node: Node) {
            self.kind = node.kind
            self.contents = node.contents
            self.childCount = node.children.count
            self.childIdentities = node.children.map { ObjectIdentifier($0) }

            // Precompute hash
            var hasher = Hasher()
            hasher.combine(kind)
            hasher.combine(contents)
            hasher.combine(childCount)
            for id in childIdentities {
                hasher.combine(id)
            }
            self.precomputedHash = hasher.finalize()
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(precomputedHash)
        }

        static func == (lhs: TreeKey, rhs: TreeKey) -> Bool {
            // Fast path: check precomputed hash first
            guard lhs.precomputedHash == rhs.precomputedHash else { return false }
            guard lhs.kind == rhs.kind else { return false }
            guard lhs.contents == rhs.contents else { return false }
            guard lhs.childCount == rhs.childCount else { return false }
            return lhs.childIdentities == rhs.childIdentities
        }
    }

    // MARK: - Storage

    /// Storage for leaf nodes (no children).
    private var leafStorage: [LeafKey: Node] = [:]

    /// Storage for tree nodes (with children).
    private var treeStorage: [TreeKey: Node] = [:]

    /// Lock for thread-safe access.
    private let lock = NSLock()

    /// Number of unique nodes in the cache.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return leafStorage.count + treeStorage.count
    }

    /// Creates a new empty cache.
    /// Use this for isolated caching scenarios. For shared caching, use `NodeCache.shared`.
    public init() {}

    // MARK: - Leaf Node Interning (No Children)

    /// Interns a leaf node with no contents and no children.
    /// Returns an existing cached node if one exists, otherwise creates and caches a new one.
    public func intern(kind: Node.Kind) -> Node {
        lock.lock()
        defer { lock.unlock() }
        return internLeafUnsafe(kind: kind, contents: .none)
    }

    /// Interns a leaf node with text contents.
    public func intern(kind: Node.Kind, text: String) -> Node {
        lock.lock()
        defer { lock.unlock() }
        return internLeafUnsafe(kind: kind, contents: .text(text))
    }

    /// Interns a leaf node with index contents.
    public func intern(kind: Node.Kind, index: UInt64) -> Node {
        lock.lock()
        defer { lock.unlock() }
        return internLeafUnsafe(kind: kind, contents: .index(index))
    }

    // MARK: - Node with Children Interning

    /// Interns a node with a single child.
    /// The child should already be interned for maximum deduplication.
    public func intern(kind: Node.Kind, child: Node) -> Node {
        lock.lock()
        defer { lock.unlock() }
        return internTreeNodeUnsafe(kind: kind, contents: .none, children: [child])
    }

    /// Interns a node with multiple children.
    /// The children should already be interned for maximum deduplication.
    public func intern(kind: Node.Kind, children: [Node]) -> Node {
        lock.lock()
        defer { lock.unlock() }
        if children.isEmpty {
            return internLeafUnsafe(kind: kind, contents: .none)
        }
        return internTreeNodeUnsafe(kind: kind, contents: .none, children: children)
    }

    /// Interns a node with text contents and children.
    public func intern(kind: Node.Kind, text: String, children: [Node]) -> Node {
        lock.lock()
        defer { lock.unlock() }
        if children.isEmpty {
            return internLeafUnsafe(kind: kind, contents: .text(text))
        }
        return internTreeNodeUnsafe(kind: kind, contents: .text(text), children: children)
    }

    /// Interns a node with index contents and children.
    public func intern(kind: Node.Kind, index: UInt64, children: [Node]) -> Node {
        lock.lock()
        defer { lock.unlock() }
        if children.isEmpty {
            return internLeafUnsafe(kind: kind, contents: .index(index))
        }
        return internTreeNodeUnsafe(kind: kind, contents: .index(index), children: children)
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
        internLeafUnsafe(kind: kind, contents: .none)
    }

    /// Interns a node with text without locking.
    public func internUnsafe(kind: Node.Kind, text: String) -> Node {
        internLeafUnsafe(kind: kind, contents: .text(text))
    }

    /// Interns a node with index without locking.
    public func internUnsafe(kind: Node.Kind, index: UInt64) -> Node {
        internLeafUnsafe(kind: kind, contents: .index(index))
    }

    /// Interns a node with children without locking.
    public func internUnsafe(kind: Node.Kind, children: [Node]) -> Node {
        if children.isEmpty {
            return internLeafUnsafe(kind: kind, contents: .none)
        }
        return internTreeNodeUnsafe(kind: kind, contents: .none, children: children)
    }

    /// Recursively interns a node tree without locking.
    public func internTreeUnsafe(_ node: Node) -> Node {
        // Leaf node: use leaf storage
        if node.children.isEmpty {
            return internLeafUnsafe(kind: node.kind, contents: node.contents)
        }

        // First, intern all children recursively (bottom-up)
        var childrenChanged = false
        var internedChildren = [Node]()
        internedChildren.reserveCapacity(node.children.count)

        for child in node.children {
            let interned = internTreeUnsafe(child)
            internedChildren.append(interned)
            if interned !== child {
                childrenChanged = true
            }
        }

        // If children changed, create a node with interned children for lookup
        if childrenChanged {
            return internTreeNodeUnsafe(kind: node.kind, contents: node.contents, children: internedChildren)
        } else {
            // Children are already canonical, try to intern this node as-is
            return internTreeNodeUnsafe(node)
        }
    }

    // MARK: - Cache Management

    /// Clears all cached nodes.
    /// Call this when you're done processing a binary to free memory.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        leafStorage.removeAll()
        treeStorage.removeAll()
    }

    /// Reserves capacity for the expected number of unique nodes.
    public func reserveCapacity(_ minimumCapacity: Int) {
        lock.lock()
        defer { lock.unlock() }
        // Assume roughly 60% leaf nodes, 40% tree nodes
        leafStorage.reserveCapacity(minimumCapacity * 6 / 10)
        treeStorage.reserveCapacity(minimumCapacity * 4 / 10)
    }

    // MARK: - Private Helpers

    private func internLeafUnsafe(kind: Node.Kind, contents: Node.Contents) -> Node {
        let key = LeafKey(kind: kind, contents: contents)
        if let existing = leafStorage[key] {
            return existing
        }
        let node = Node(kind: kind, contents: contents)
        leafStorage[key] = node
        return node
    }

    private func internTreeNodeUnsafe(kind: Node.Kind, contents: Node.Contents, children: [Node]) -> Node {
        let node = Node(kind: kind, contents: contents, children: children)
        return internTreeNodeUnsafe(node)
    }

    private func internTreeNodeUnsafe(_ node: Node) -> Node {
        let key = TreeKey(node)
        if let existing = treeStorage[key] {
            return existing
        }
        treeStorage[key] = node
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

