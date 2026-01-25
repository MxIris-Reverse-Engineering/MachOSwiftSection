import SwiftStdlibToolbox

/// A node in the demangled symbol tree.
///
/// Thread safety: Node is safe to read from multiple threads after demangling is complete.
/// All modifications happen during the single-threaded demangling process.
public final class Node: @unchecked Sendable {
    public enum Contents: Hashable, Sendable {
        case none
        case index(UInt64)
        case text(String)
    }

    public let kind: Kind

    public let contents: Contents

    /// The parent node in the tree. Only modified during demangling.
    public nonisolated(unsafe) private(set) weak var parent: Node?

    /// Child nodes. Only modified during demangling.
    public nonisolated(unsafe) private(set) var children: [Node] = []

    public init(kind: Kind, contents: Contents = .none, children: [Node] = []) {
        self.kind = kind
        self.contents = contents
        self.children = children
        for child in children {
            child.parent = self
        }
    }

    public func copy() -> Node {
        let copy = Node(kind: kind, contents: contents, children: children.map { $0.copy() })
        copy.parent = parent
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
        return Node(kind: kind, contents: contents, children: modifiedChildren)
    }

    func changeKind(_ newKind: Kind, additionalChildren: [Node] = []) -> Node {
        if case .text(let text) = contents {
            return Node(kind: newKind, contents: .text(text), children: children + additionalChildren)
        } else if case .index(let i) = contents {
            return Node(kind: newKind, contents: .index(i), children: children + additionalChildren)
        } else {
            return Node(kind: newKind, contents: .none, children: children + additionalChildren)
        }
    }

    func addChild(_ newChild: Node) {
        newChild.parent = self
        children.append(newChild)
    }

    func removeChild(at index: Int) {
        guard children.indices.contains(index) else { return }
        children.remove(at: index)
    }

    func insertChild(_ newChild: Node, at index: Int) {
        guard index >= 0, index <= children.count else { return }
        newChild.parent = self
        children.insert(newChild, at: index)
    }

    func addChildren(_ newChildren: [Node]) {
        for child in newChildren {
            child.parent = self
        }
        children.append(contentsOf: newChildren)
    }

    func setChildren(_ newChildren: [Node]) {
        for child in newChildren {
            child.parent = self
        }
        children = newChildren
    }

    func setChild(_ child: Node, at index: Int) {
        guard children.indices.contains(index) else { return }
        child.parent = self
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
        Node(kind: kind, contents: contents, children: children + [newChild])
    }

    /// Returns a new node with the child removed at the specified index.
    func removingChild(at index: Int) -> Node {
        guard children.indices.contains(index) else { return self }
        var modifiedChildren = children
        modifiedChildren.remove(at: index)
        return Node(kind: kind, contents: contents, children: modifiedChildren)
    }

    /// Returns a new node with the child inserted at the specified index.
    func insertingChild(_ newChild: Node, at index: Int) -> Node {
        guard index >= 0, index <= children.count else { return self }
        var modifiedChildren = children
        modifiedChildren.insert(newChild, at: index)
        return Node(kind: kind, contents: contents, children: modifiedChildren)
    }

    /// Returns a new node with the children added.
    func addingChildren(_ newChildren: [Node]) -> Node {
        Node(kind: kind, contents: contents, children: children + newChildren)
    }

    /// Returns a new node with the specified children.
    func withChildren(_ newChildren: [Node]) -> Node {
        Node(kind: kind, contents: contents, children: newChildren)
    }

    /// Returns a new node with the child replaced at the specified index.
    func withChild(_ child: Node, at index: Int) -> Node {
        guard children.indices.contains(index) else { return self }
        var modifiedChildren = children
        modifiedChildren[index] = child
        return Node(kind: kind, contents: contents, children: modifiedChildren)
    }

    /// Returns a new node with children reversed.
    func reversingChildren() -> Node {
        Node(kind: kind, contents: contents, children: children.reversed())
    }

    /// Returns a new node with the first N children reversed.
    func reversingFirst(_ count: Int) -> Node {
        var modifiedChildren = children
        modifiedChildren.reverseFirst(count)
        return Node(kind: kind, contents: contents, children: modifiedChildren)
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
