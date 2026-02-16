import SwiftStdlibToolbox

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

extension Node {
    @inlinable
    public static func create(kind: Kind, contents: Contents = .none, @ArrayBuilder<Node> childrenBuilder: () -> [Node]) -> Node {
        create(kind: kind, contents: contents, children: childrenBuilder())
    }

    @inlinable
    public static func create(kind: Kind, text: String, @ArrayBuilder<Node> childrenBuilder: () -> [Node]) -> Node {
        create(kind: kind, contents: .text(text), children: childrenBuilder())
    }

    @inlinable
    public static func create(kind: Kind, index: UInt64, @ArrayBuilder<Node> childrenBuilder: () -> [Node]) -> Node {
        create(kind: kind, contents: .index(index), children: childrenBuilder())
    }
}
