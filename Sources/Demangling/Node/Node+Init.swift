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

// MARK: - Factory Methods (with automatic leaf interning)

extension Node {
    /// Creates a node. Leaf nodes (no children) are automatically interned via `NodeCache.shared`.
    @inlinable
    public static func create(kind: Kind, contents: Contents = .none, children: [Node] = []) -> Node {
        NodeCache.shared.createInterned(kind: kind, contents: contents, children: children)
    }

    /// Creates a node from inline children. Leaf nodes are automatically interned.
    @inlinable
    public static func create(kind: Kind, contents: Contents = .none, inlineChildren: NodeChildren) -> Node {
        NodeCache.shared.createInterned(kind: kind, contents: contents, inlineChildren: inlineChildren)
    }

    @inlinable
    public static func create(kind: Kind, child: Node) -> Node {
        create(kind: kind, contents: .none, children: [child])
    }

    @inlinable
    public static func create(kind: Kind, text: String, child: Node) -> Node {
        create(kind: kind, contents: .text(text), children: [child])
    }

    @inlinable
    public static func create(kind: Kind, text: String, children: [Node] = []) -> Node {
        create(kind: kind, contents: .text(text), children: children)
    }

    @inlinable
    public static func create(kind: Kind, index: UInt64, child: Node) -> Node {
        create(kind: kind, contents: .index(index), children: [child])
    }

    @inlinable
    public static func create(kind: Kind, index: UInt64, children: [Node] = []) -> Node {
        create(kind: kind, contents: .index(index), children: children)
    }

    /// Compound factory: creates `.type` wrapping a node of `typeWithChildKind` with a single child.
    /// Uses `create()` for intermediate nodes to ensure inline interning.
    static func create(typeWithChildKind: Kind, childChild: Node) -> Node {
        create(kind: .type, children: [create(kind: typeWithChildKind, children: [childChild])])
    }

    /// Compound factory: creates `.type` wrapping a node of `typeWithChildKind` with children.
    static func create(typeWithChildKind: Kind, childChildren: [Node]) -> Node {
        create(kind: .type, children: [create(kind: typeWithChildKind, children: childChildren)])
    }

    /// Compound factory: creates a Swift stdlib type node (`.type` > `kind` > [`.module("Swift")`, `.identifier(name)`]).
    static func create(swiftStdlibTypeKind: Kind, name: String) -> Node {
        create(kind: .type, children: [create(kind: swiftStdlibTypeKind, children: [
            create(kind: .module, text: stdlibName),
            create(kind: .identifier, text: name),
        ])])
    }

    /// Compound factory: creates a Swift builtin type node (`.type` > `kind(name)`).
    static func create(swiftBuiltinType: Kind, name: String) -> Node {
        create(kind: .type, children: [create(kind: swiftBuiltinType, text: name)])
    }
}
