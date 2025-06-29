extension Node: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(contents)
        hasher.combine(children)
    }

    public static func == (lhs: Node, rhs: Node) -> Bool {
        return lhs.kind == rhs.kind && lhs.contents == rhs.contents && lhs.children == rhs.children
    }
}
