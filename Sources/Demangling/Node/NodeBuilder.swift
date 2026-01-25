import Foundation

/// A thread-safe builder for modifying Node trees.
///
/// External modules must use this class to modify nodes, ensuring thread safety.
/// The Demangling module can directly modify nodes during the single-threaded demangling process.
///
/// Example usage:
/// ```swift
/// let builder = NodeBuilder(existingNode)
/// builder
///     .addChild(childNode)
///     .insertChild(anotherChild, at: 0)
///
/// let result = builder.node
/// ```
public final class NodeBuilder: @unchecked Sendable {
    private let _lock: UnsafeMutablePointer<os_unfair_lock>
    private var _node: Node

    /// The current node being built.
    public var node: Node {
        withLock { _node }
    }

    /// Creates a builder with a copy of the given node.
    public init(_ node: Node) {
        self._lock = .allocate(capacity: 1)
        self._lock.initialize(to: os_unfair_lock())
        self._node = node.copy()
    }

    /// Creates a builder with a new node.
    public init(kind: Node.Kind, contents: Node.Contents = .none, children: [Node] = []) {
        self._lock = .allocate(capacity: 1)
        self._lock.initialize(to: os_unfair_lock())
        self._node = Node(kind: kind, contents: contents, children: children)
    }

    deinit {
        _lock.deinitialize(count: 1)
        _lock.deallocate()
    }

    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(_lock)
        defer { os_unfair_lock_unlock(_lock) }
        return body()
    }

    // MARK: - Mutating Operations

    /// Adds a child node.
    @discardableResult
    public func addChild(_ child: Node) -> Self {
        withLock { _node.addChild(child) }
        return self
    }

    /// Adds multiple child nodes.
    @discardableResult
    public func addChildren(_ children: [Node]) -> Self {
        withLock { _node.addChildren(children) }
        return self
    }

    /// Inserts a child node at the specified index.
    @discardableResult
    public func insertChild(_ child: Node, at index: Int) -> Self {
        withLock { _node.insertChild(child, at: index) }
        return self
    }

    /// Removes the child at the specified index.
    @discardableResult
    public func removeChild(at index: Int) -> Self {
        withLock { _node.removeChild(at: index) }
        return self
    }

    /// Sets a child at the specified index.
    @discardableResult
    public func setChild(_ child: Node, at index: Int) -> Self {
        withLock { _node.setChild(child, at: index) }
        return self
    }

    /// Replaces all children with the specified nodes.
    @discardableResult
    public func setChildren(_ children: [Node]) -> Self {
        withLock { _node.setChildren(children) }
        return self
    }

    /// Reverses all children.
    @discardableResult
    public func reverseChildren() -> Self {
        withLock { _node.reverseChildren() }
        return self
    }

    /// Reverses the first N children.
    @discardableResult
    public func reverseFirst(_ count: Int) -> Self {
        withLock { _node.reverseFirst(count) }
        return self
    }

    // MARK: - Non-mutating Operations (return new Node)

    /// Returns a new node with the child added.
    public func addingChild(_ child: Node) -> Node {
        withLock { _node.addingChild(child) }
    }

    /// Returns a new node with the children added.
    public func addingChildren(_ children: [Node]) -> Node {
        withLock { _node.addingChildren(children) }
    }

    /// Returns a new node with the child inserted.
    public func insertingChild(_ child: Node, at index: Int) -> Node {
        withLock { _node.insertingChild(child, at: index) }
    }

    /// Returns a new node with the child removed.
    public func removingChild(at index: Int) -> Node {
        withLock { _node.removingChild(at: index) }
    }

    /// Returns a new node with the child replaced.
    public func withChild(_ child: Node, at index: Int) -> Node {
        withLock { _node.withChild(child, at: index) }
    }

    /// Returns a new node with the specified children.
    public func withChildren(_ children: [Node]) -> Node {
        withLock { _node.withChildren(children) }
    }

    /// Returns a new node with children reversed.
    public func reversingChildren() -> Node {
        withLock { _node.reversingChildren() }
    }

    /// Returns a new node with the first N children reversed.
    public func reversingFirst(_ count: Int) -> Node {
        withLock { _node.reversingFirst(count) }
    }

    /// Returns a new node with the descendant replaced.
    public func replacingDescendant(_ old: Node, with new: Node) -> Node {
        withLock { _node.replacingDescendant(old, with: new) }
    }

    // MARK: - Transformations

    /// Returns a new node with a different kind.
    public func changingKind(_ newKind: Node.Kind, additionalChildren: [Node] = []) -> Node {
        withLock { _node.changeKind(newKind, additionalChildren: additionalChildren) }
    }

    /// Returns a new node with the child at index replaced or removed.
    public func changingChild(_ newChild: Node?, at index: Int) -> Node {
        withLock { _node.changeChild(newChild, at: index) }
    }

    /// Returns a copy of the current node.
    public func copy() -> Node {
        withLock { _node.copy() }
    }

    /// Finalizes and returns the built node.
    /// After calling this, the builder should not be used.
    public func build() -> Node {
        withLock { _node }
    }
}
