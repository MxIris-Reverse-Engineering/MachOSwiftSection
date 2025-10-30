import SwiftStdlibToolbox

public final class Node: Sendable {
    public enum Contents: Hashable, Sendable {
        case none
        case index(UInt64)
        case text(String)
    }

    public let kind: Kind

    public let contents: Contents

    @Mutex
    public private(set) weak var parent: Node?

    @Mutex
    public private(set) var children: [Node] = []

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
    package func changeChild(_ newChild: Node?, at index: Int) -> Node {
        guard children.indices.contains(index) else { return self }

        var modifiedChildren = children
        if let nc = newChild {
            modifiedChildren[index] = nc
        } else {
            modifiedChildren.remove(at: index)
        }
        return Node(kind: kind, contents: contents, children: modifiedChildren)
    }

    package func changeKind(_ newKind: Kind, additionalChildren: [Node] = []) -> Node {
        if case .text(let text) = contents {
            return Node(kind: newKind, contents: .text(text), children: children + additionalChildren)
        } else if case .index(let i) = contents {
            return Node(kind: newKind, contents: .index(i), children: children + additionalChildren)
        } else {
            return Node(kind: newKind, contents: .none, children: children + additionalChildren)
        }
    }

    package func addChild(_ newChild: Node) {
        newChild.parent = self
        children.append(newChild)
    }

    package func removeChild(at index: Int) {
        guard children.indices.contains(index) else { return }
        children.remove(at: index)
    }

    package func insertChild(_ newChild: Node, at index: Int) {
        guard index >= 0, index <= children.count else { return }
        newChild.parent = self
        children.insert(newChild, at: index)
    }

    package func addChildren(_ newChildren: [Node]) {
        for child in newChildren {
            child.parent = self
        }
        children.append(contentsOf: newChildren)
    }

    package func setChildren(_ newChildren: [Node]) {
        for child in newChildren {
            child.parent = self
        }
        children = newChildren
    }

    package func setChild(_ child: Node, at index: Int) {
        guard children.indices.contains(index) else { return }
        child.parent = self
        children[index] = child
    }

    package func reverseChildren() {
        children.reverse()
    }

    package func reverseFirst(_ count: Int) {
        children.reverseFirst(count)
    }
}
