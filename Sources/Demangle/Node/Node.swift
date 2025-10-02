import SwiftStdlibToolbox

public final class Node: Sendable {
    public let kind: Kind

    public let contents: Contents

    @Mutex
    public private(set) weak var parent: Node?

    @Mutex
    public private(set) var children: [Node] = []

    public enum Contents: Hashable, Sendable {
        case none
        case index(UInt64)
        case text(String)

        public var hasText: Bool {
            text != nil
        }

        public var text: String? {
            switch self {
            case .none:
                return nil
            case .index:
                return nil
            case .text(let string):
                return string
            }
        }
    }

    package func copy() -> Node {
        let copy = Node(kind: kind, contents: contents, children: children.map { $0.copy() })
        copy.parent = parent
        return copy
    }
    
    public init(kind: Kind, contents: Contents = .none, children: [Node] = []) {
        self.kind = kind
        self.contents = contents
        self.children = children
        for child in children {
            child.parent = self
        }
    }

    package convenience init(kind: Kind, child: Node) {
        self.init(kind: kind, contents: .none, children: [child])
    }
    
    package convenience init(kind: Kind, children: [Node] = []) {
        self.init(kind: kind, contents: .none, children: children)
    }
    
    package convenience init(kind: Kind, text: String, child: Node) {
        self.init(kind: kind, contents: .text(text), children: [child])
    }
    
    package convenience init(kind: Kind, text: String, children: [Node] = []) {
        self.init(kind: kind, contents: .text(text), children: children)
    }
    
    package convenience init(kind: Kind, index: UInt64, child: Node) {
        self.init(kind: kind, contents: .index(index), children: [child])
    }
    
    package convenience init(kind: Kind, index: UInt64, children: [Node] = []) {
        self.init(kind: kind, contents: .index(index), children: children)
    }
    
    package convenience init(typeWithChildKind: Kind, childChild: Node) {
        self.init(kind: .type, contents: .none, children: [Node(kind: typeWithChildKind, children: [childChild])])
    }

    package convenience init(typeWithChildKind: Kind, childChildren: [Node]) {
        self.init(kind: .type, contents: .none, children: [Node(kind: typeWithChildKind, children: childChildren)])
    }

    package convenience init(swiftStdlibTypeKind: Kind, name: String) {
        self.init(kind: .type, contents: .none, children: [Node(kind: swiftStdlibTypeKind, children: [
            Node(kind: .module, contents: .text(stdlibName)),
            Node(kind: .identifier, contents: .text(name)),
        ])])
    }

    package convenience init(swiftBuiltinType: Kind, name: String) {
        self.init(kind: .type, children: [Node(kind: swiftBuiltinType, contents: .text(name))])
    }
    
    package subscript(index: Int) -> Node? {
        get { children[safe: index] }
    }
}

extension Node {
    package func changeChild(_ newChild: Node?, atIndex: Int) -> Node {
        guard children.indices.contains(atIndex) else { return self }

        var modifiedChildren = children
        if let nc = newChild {
            modifiedChildren[atIndex] = nc
        } else {
            modifiedChildren.remove(at: atIndex)
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
