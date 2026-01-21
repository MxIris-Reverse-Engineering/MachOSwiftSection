extension Node {
    open class Rewriter {
        public init() {}

        public final func rewrite(_ node: Node) -> Node {
            let originalChildren = node.children
            var newChildren: [Node] = []
            newChildren.reserveCapacity(originalChildren.count)

            var hasChildrenChanged = false

            for child in originalChildren {
                let rewrittenChild = rewrite(child)
                newChildren.append(rewrittenChild)

                if rewrittenChild !== child {
                    hasChildrenChanged = true
                }
            }

            let nodeToVisit: Node

            if hasChildrenChanged {
                nodeToVisit = Node(
                    kind: node.kind,
                    contents: node.contents,
                    children: newChildren
                )
            } else {
                nodeToVisit = node
            }

            return visit(nodeToVisit)
        }

        open func visit(_ node: Node) -> Node {
            return node
        }
    }
}
