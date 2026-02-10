import SwiftStdlibToolbox

/// A node in the demangled symbol tree.
///
/// Thread safety: Node is safe to read from multiple threads after demangling is complete.
/// All modifications happen during the single-threaded demangling process.
///
/// Internally uses a unified `Payload` enum that merges contents and children
/// storage into a single discriminated union, mirroring the C++ Swift runtime's
/// approach where `Text`/`Index`/`InlineChildren`/`Children` share a `union`.
/// This saves ~24 bytes per node compared to storing them separately.
public final class Node: Sendable {
    /// Legacy contents type preserved for API compatibility.
    public enum Contents: Hashable, Sendable {
        case none
        case index(UInt64)
        case text(String)
    }

    /// Unified storage that is either contents (text/index) or children, never both.
    /// Mirrors the C++ Swift runtime's union where Text/Index/InlineChildren/Children
    /// are mutually exclusive.
    @usableFromInline
    enum Payload: Sendable {
        case none
        case index(UInt64)
        case text(String)
        case oneChild(Node)
        case twoChildren(Node, Node)
        case manyChildren(ContiguousArray<Node>)
    }

    public let kind: Kind

    /// Unified payload storage. Only modified during demangling for child mutations.
    @usableFromInline
    nonisolated(unsafe) var payload: Payload

    /// Raw parent pointer — avoids weak reference side table allocation (saves ~48 bytes per node).
    /// Safety: Parent always outlives children (parent holds strong refs via `children` array).
    nonisolated(unsafe) private var _parent: Unmanaged<Node>?

    /// The parent node in the tree. Only modified during demangling.
    public var parent: Node? {
        _parent?.takeUnretainedValue()
    }

    /// The contents of this node (text, index, or none).
    @inlinable
    public var contents: Contents {
        switch payload {
        case .none, .oneChild, .twoChildren, .manyChildren:
            return .none
        case .index(let i):
            return .index(i)
        case .text(let s):
            return .text(s)
        }
    }

    /// Child nodes. Only modified during demangling.
    public var children: NodeChildren {
        @inlinable get {
            switch payload {
            case .none, .index, .text:
                return NodeChildren()
            case .oneChild(let n):
                return NodeChildren(n)
            case .twoChildren(let n0, let n1):
                return NodeChildren(n0, n1)
            case .manyChildren(let children):
                return NodeChildren(children)
            }
        }
        set {
            payload = Self.mergedPayload(contents: contents, children: newValue)
            for child in newValue {
                child._parent = .passUnretained(self)
            }
        }
    }

    /// Merge contents and children into the most compact payload case.
    /// When children are present, they take priority (contents and children are mutually exclusive).
    @usableFromInline
    static func mergedPayload(contents: Contents, children: NodeChildren) -> Payload {
        if children.count > 0 {
            switch children.count {
            case 1: return .oneChild(children[0])
            case 2: return .twoChildren(children[0], children[1])
            default: return .manyChildren(children.toContiguousArray())
            }
        }
        switch contents {
        case .none: return .none
        case .index(let i): return .index(i)
        case .text(let s): return .text(s)
        }
    }

    public init(kind: Kind, contents: Contents = .none, children: [Node] = []) {
        self.kind = kind
        self.payload = Self.mergedPayload(contents: contents, children: NodeChildren(children))
        for child in self.children {
            child._parent = .passUnretained(self)
        }
    }

    public init(kind: Kind, contents: Contents = .none, inlineChildren: NodeChildren) {
        self.kind = kind
        self.payload = Self.mergedPayload(contents: contents, children: inlineChildren)
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

    /// Optimized addChild that mutates payload directly for the common
    /// children-only cases, avoiding a full get/rebuild/set round-trip.
    func addChild(_ newChild: Node) {
        newChild._parent = .passUnretained(self)
        switch payload {
        case .none:
            payload = .oneChild(newChild)
        case .oneChild(let n):
            payload = .twoChildren(n, newChild)
        case .twoChildren(let n0, let n1):
            payload = .manyChildren(ContiguousArray([n0, n1, newChild]))
        case .manyChildren(var arr):
            arr.append(newChild)
            payload = .manyChildren(arr)
        default:
            // Rare path: node has both contents and children
            var c = children
            c.append(newChild)
            payload = Self.mergedPayload(contents: contents, children: c)
        }
    }

    func removeChild(at index: Int) {
        guard children.indices.contains(index) else { return }
        var c = children
        c.remove(at: index)
        payload = Self.mergedPayload(contents: contents, children: c)
    }

    func insertChild(_ newChild: Node, at index: Int) {
        guard index >= 0, index <= children.count else { return }
        newChild._parent = .passUnretained(self)
        var c = children
        c.insert(newChild, at: index)
        payload = Self.mergedPayload(contents: contents, children: c)
    }

    func addChildren(_ newChildren: [Node]) {
        for child in newChildren {
            child._parent = .passUnretained(self)
        }
        var c = children
        c.append(contentsOf: newChildren)
        payload = Self.mergedPayload(contents: contents, children: c)
    }

    func addChildren(_ newChildren: NodeChildren) {
        for child in newChildren {
            child._parent = .passUnretained(self)
        }
        var c = children
        c.append(contentsOf: newChildren)
        payload = Self.mergedPayload(contents: contents, children: c)
    }

    func setChildren(_ newChildren: [Node]) {
        for child in newChildren {
            child._parent = .passUnretained(self)
        }
        payload = Self.mergedPayload(contents: contents, children: NodeChildren(newChildren))
    }

    func setChild(_ child: Node, at index: Int) {
        guard children.indices.contains(index) else { return }
        child._parent = .passUnretained(self)
        var c = children
        c[index] = child
        payload = Self.mergedPayload(contents: contents, children: c)
    }

    func reverseChildren() {
        var c = children
        c.reverse()
        payload = Self.mergedPayload(contents: contents, children: c)
    }

    func reverseFirst(_ count: Int) {
        var c = children
        c.reverseFirst(count)
        payload = Self.mergedPayload(contents: contents, children: c)
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
