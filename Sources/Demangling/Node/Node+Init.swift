import SwiftStdlibToolbox

extension Node {
    public convenience init(kind: Kind, child: Node) {
        self.init(kind: kind, contents: .none, children: [child])
    }

    public convenience init(kind: Kind, children: [Node] = []) {
        self.init(kind: kind, contents: .none, children: children)
    }

    public convenience init(kind: Kind, text: String, child: Node) {
        self.init(kind: kind, contents: .text(text), children: [child])
    }

    public convenience init(kind: Kind, text: String, children: [Node] = []) {
        self.init(kind: kind, contents: .text(text), children: children)
    }

    public convenience init(kind: Kind, index: UInt64, child: Node) {
        self.init(kind: kind, contents: .index(index), children: [child])
    }

    public convenience init(kind: Kind, index: UInt64, children: [Node] = []) {
        self.init(kind: kind, contents: .index(index), children: children)
    }

    convenience init(typeWithChildKind: Kind, childChild: Node) {
        self.init(kind: .type, contents: .none, children: [Node(kind: typeWithChildKind, children: [childChild])])
    }

    convenience init(typeWithChildKind: Kind, childChildren: [Node]) {
        self.init(kind: .type, contents: .none, children: [Node(kind: typeWithChildKind, children: childChildren)])
    }

    convenience init(swiftStdlibTypeKind: Kind, name: String) {
        self.init(kind: .type, contents: .none, children: [Node(kind: swiftStdlibTypeKind, children: [
            Node(kind: .module, contents: .text(stdlibName)),
            Node(kind: .identifier, contents: .text(name)),
        ])])
    }

    convenience init(swiftBuiltinType: Kind, name: String) {
        self.init(kind: .type, children: [Node(kind: swiftBuiltinType, contents: .text(name))])
    }
}

extension Node {
    public convenience init(kind: Kind, contents: Contents = .none, @ArrayBuilder<Node> childrenBuilder: () -> [Node]) {
        self.init(kind: kind, contents: contents, children: childrenBuilder())
    }

    public convenience init(kind: Kind, text: String, @ArrayBuilder<Node> childrenBuilder: () -> [Node]) {
        self.init(kind: kind, contents: .text(text), children: childrenBuilder())
    }

    public convenience init(kind: Kind, index: UInt64, @ArrayBuilder<Node> childrenBuilder: () -> [Node]) {
        self.init(kind: kind, contents: .index(index), children: childrenBuilder())
    }
}

// MARK: - Factory Methods

extension Node {
    public static func create(kind: Kind, contents: Contents = .none, children: [Node] = []) -> Node {
        Node(kind: kind, contents: contents, children: children)
    }

    public static func create(kind: Kind, contents: Contents = .none, inlineChildren: NodeChildren) -> Node {
        Node(kind: kind, contents: contents, inlineChildren: inlineChildren)
    }

    public static func create(kind: Kind, child: Node) -> Node {
        Node(kind: kind, child: child)
    }

    public static func create(kind: Kind, text: String, child: Node) -> Node {
        Node(kind: kind, text: text, child: child)
    }

    public static func create(kind: Kind, text: String, children: [Node] = []) -> Node {
        Node(kind: kind, text: text, children: children)
    }

    public static func create(kind: Kind, index: UInt64, child: Node) -> Node {
        Node(kind: kind, index: index, child: child)
    }

    public static func create(kind: Kind, index: UInt64, children: [Node] = []) -> Node {
        Node(kind: kind, index: index, children: children)
    }

    static func create(typeWithChildKind: Kind, childChild: Node) -> Node {
        Node(typeWithChildKind: typeWithChildKind, childChild: childChild)
    }

    static func create(typeWithChildKind: Kind, childChildren: [Node]) -> Node {
        Node(typeWithChildKind: typeWithChildKind, childChildren: childChildren)
    }

    static func create(swiftStdlibTypeKind: Kind, name: String) -> Node {
        Node(swiftStdlibTypeKind: swiftStdlibTypeKind, name: name)
    }

    static func create(swiftBuiltinType: Kind, name: String) -> Node {
        Node(swiftBuiltinType: swiftBuiltinType, name: name)
    }
}
