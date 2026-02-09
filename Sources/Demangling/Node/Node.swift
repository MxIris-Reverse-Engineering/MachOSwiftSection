import SwiftStdlibToolbox

/// A node in the demangled symbol tree.
///
/// Thread safety: Node is safe to read from multiple threads after demangling is complete.
/// All modifications happen during the single-threaded demangling process.
public final class Node: Sendable {
    public enum Contents: Hashable, Sendable {
        case none
        case index(UInt64)
        case text(String)
    }

    public let kind: Kind

    public let contents: Contents

    /// Raw parent pointer — avoids weak reference side table allocation (saves ~48 bytes per node).
    /// Safety: Parent always outlives children (parent holds strong refs via `children` array).
    nonisolated(unsafe) private var _parent: Unmanaged<Node>?

    /// The parent node in the tree. Only modified during demangling.
    public var parent: Node? {
        _parent?.takeUnretainedValue()
    }

    /// Child nodes stored inline for 0–2 children. Only modified during demangling.
    nonisolated(unsafe) public private(set) var children: NodeChildren = .init()

    public init(kind: Kind, contents: Contents = .none, children: [Node] = []) {
        self.kind = kind
        self.contents = contents
        self.children = NodeChildren(children)
        for child in self.children {
            child._parent = .passUnretained(self)
        }
    }

    public init(kind: Kind, contents: Contents = .none, inlineChildren: NodeChildren) {
        self.kind = kind
        self.contents = contents
        self.children = inlineChildren
        for child in self.children {
            child._parent = .passUnretained(self)
        }
    }

    public func copy() -> Node {
        let copiedChildren = NodeChildren(children.map { $0.copy() })
        let copy = Node(kind: kind, contents: contents, inlineChildren: copiedChildren)
        copy._parent = _parent
        return copy
    }
}

extension Node {
    func changeChild(_ newChild: Node?, at index: Int) -> Node {
        guard children.indices.contains(index) else { return self }

        var modifiedChildren = children
        if let nc = newChild {
            modifiedChildren[index] = nc
        } else {
            modifiedChildren.remove(at: index)
        }
        return Node(kind: kind, contents: contents, inlineChildren: modifiedChildren)
    }

    func changeKind(_ newKind: Kind, additionalChildren: [Node] = []) -> Node {
        let newChildren = children + additionalChildren
        return Node(kind: newKind, contents: contents, inlineChildren: newChildren)
    }

    func addChild(_ newChild: Node) {
        newChild._parent = .passUnretained(self)
        children.append(newChild)
    }

    func removeChild(at index: Int) {
        guard children.indices.contains(index) else { return }
        children.remove(at: index)
    }

    func insertChild(_ newChild: Node, at index: Int) {
        guard index >= 0, index <= children.count else { return }
        newChild._parent = .passUnretained(self)
        children.insert(newChild, at: index)
    }

    func addChildren(_ newChildren: [Node]) {
        for child in newChildren {
            child._parent = .passUnretained(self)
        }
        children.append(contentsOf: newChildren)
    }

    func addChildren(_ newChildren: NodeChildren) {
        for child in newChildren {
            child._parent = .passUnretained(self)
        }
        children.append(contentsOf: newChildren)
    }

    func setChildren(_ newChildren: [Node]) {
        for child in newChildren {
            child._parent = .passUnretained(self)
        }
        children = NodeChildren(newChildren)
    }

    func setChild(_ child: Node, at index: Int) {
        guard children.indices.contains(index) else { return }
        child._parent = .passUnretained(self)
        children[index] = child
    }

    func reverseChildren() {
        children.reverse()
    }

    func reverseFirst(_ count: Int) {
        children.reverseFirst(count)
    }
}

// MARK: - Non-mutating (copying) versions
// These are internal - external modules should use NodeBuilder

extension Node {
    /// Returns a new node with the child added.
    func addingChild(_ newChild: Node) -> Node {
        var nc = children
        nc.append(newChild)
        return Node(kind: kind, contents: contents, inlineChildren: nc)
    }

    /// Returns a new node with the child removed at the specified index.
    func removingChild(at index: Int) -> Node {
        guard children.indices.contains(index) else { return self }
        var nc = children
        nc.remove(at: index)
        return Node(kind: kind, contents: contents, inlineChildren: nc)
    }

    /// Returns a new node with the child inserted at the specified index.
    func insertingChild(_ newChild: Node, at index: Int) -> Node {
        guard index >= 0, index <= children.count else { return self }
        var nc = children
        nc.insert(newChild, at: index)
        return Node(kind: kind, contents: contents, inlineChildren: nc)
    }

    /// Returns a new node with the children added.
    func addingChildren(_ newChildren: [Node]) -> Node {
        let nc = children + newChildren
        return Node(kind: kind, contents: contents, inlineChildren: nc)
    }

    /// Returns a new node with the specified children.
    func withChildren(_ newChildren: [Node]) -> Node {
        Node(kind: kind, contents: contents, children: newChildren)
    }

    /// Returns a new node with the child replaced at the specified index.
    func withChild(_ child: Node, at index: Int) -> Node {
        guard children.indices.contains(index) else { return self }
        var nc = children
        nc[index] = child
        return Node(kind: kind, contents: contents, inlineChildren: nc)
    }

    /// Returns a new node with children reversed.
    func reversingChildren() -> Node {
        var nc = children
        nc.reverse()
        return Node(kind: kind, contents: contents, inlineChildren: nc)
    }

    /// Returns a new node with the first N children reversed.
    func reversingFirst(_ count: Int) -> Node {
        var nc = children
        nc.reverseFirst(count)
        return Node(kind: kind, contents: contents, inlineChildren: nc)
    }

    /// Returns a new tree with the descendant node replaced.
    /// If `old` is not found in the tree, returns a copy of self.
    func replacingDescendant(_ old: Node, with new: Node) -> Node {
        if self === old {
            return new
        }
        let newChildren = children.map { $0.replacingDescendant(old, with: new) }
        return Node(kind: kind, contents: contents, children: newChildren)
    }
}
