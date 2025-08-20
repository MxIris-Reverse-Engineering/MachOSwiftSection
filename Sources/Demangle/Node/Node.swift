import Utilities
import Mutex

public final class Node: Sendable {
    public let kind: Kind
    
    public let contents: Contents
    
    private struct WeakBox {
        weak var wrappedValue: Node?
    }
    
    private let _parentMutex: Mutex<WeakBox> = .init(.init())
    
    private var _parent: Node? {
        set { _parentMutex.withLock { $0.wrappedValue = newValue } }
        get { _parentMutex.withLock { $0.wrappedValue } }
    }
    
    public var parent: Node? { _parent }
    
    private let _childrenMutex: Mutex<[Node]>
    
    private var _children: [Node] {
        set { _childrenMutex.withLock { $0 = newValue } }
        get { _childrenMutex.withLock { $0 } }
    }
    
    public var children: [Node] { _children }

    public enum Contents: Hashable, Sendable {
        case none
        case index(UInt64)
        case name(String)

        public var hasName: Bool {
            name != nil
        }

        public var name: String? {
            switch self {
            case .none:
                return nil
            case .index:
                return nil
            case .name(let string):
                return string
            }
        }
    }

    public init(kind: Kind, contents: Contents = .none, children: [Node] = []) {
        self.kind = kind
        self._childrenMutex = .init(children)
        self.contents = contents
        for child in children {
            child._parent = self
        }
    }

    package convenience init(kind: Kind, child: Node) {
        self.init(kind: kind, contents: .none, children: [child])
    }

    package convenience init(typeWithChildKind: Kind, childChild: Node) {
        self.init(kind: .type, contents: .none, children: [Node(kind: typeWithChildKind, children: [childChild])])
    }

    package convenience init(typeWithChildKind: Kind, childChildren: [Node]) {
        self.init(kind: .type, contents: .none, children: [Node(kind: typeWithChildKind, children: childChildren)])
    }

    package convenience init(swiftStdlibTypeKind: Kind, name: String) {
        self.init(kind: .type, contents: .none, children: [Node(kind: swiftStdlibTypeKind, children: [
            Node(kind: .module, contents: .name(stdlibName)),
            Node(kind: .identifier, contents: .name(name)),
        ])])
    }

    package convenience init(swiftBuiltinType: Kind, name: String) {
        self.init(kind: .type, children: [Node(kind: swiftBuiltinType, contents: .name(name))])
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
        if case .name(let text) = contents {
            return Node(kind: newKind, contents: .name(text), children: children + additionalChildren)
        } else if case .index(let i) = contents {
            return Node(kind: newKind, contents: .index(i), children: children + additionalChildren)
        } else {
            return Node(kind: newKind, contents: .none, children: children + additionalChildren)
        }
    }

    package func addChild(_ newChild: Node) {
        newChild._parent = self
        _children.append(newChild)
    }

    package func removeChild(at index: Int) {
        guard children.indices.contains(index) else { return }
        _children.remove(at: index)
    }

    package func insertChild(_ newChild: Node, at index: Int) {
        guard index >= 0, index <= children.count else { return }
        newChild._parent = self
        _children.insert(newChild, at: index)
    }

    package func addChildren(_ newChildren: [Node]) {
        for child in newChildren {
            child._parent = self
        }
        _children.append(contentsOf: newChildren)
    }

    package func setChildren(_ newChildren: [Node]) {
        for child in newChildren {
            child._parent = self
        }
        _children = newChildren
    }

    package func setChild(_ child: Node, at index: Int) {
        guard children.indices.contains(index) else { return }
        child._parent = self
        _children[index] = child
    }

    package func reverseChildren() {
        _children.reverse()
    }

    package func reverseFirst(_ count: Int) {
        _children.reverseFirst(count)
    }
}
