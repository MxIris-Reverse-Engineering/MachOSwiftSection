package struct NodePrintContext {
    package let node: Node?
    package let parentKind: Node.Kind?
    package let state: NodePrintState

    package static func context(for node: Node? = nil, parentKind: Node.Kind? = nil, state: NodePrintState) -> NodePrintContext {
        NodePrintContext(node: node, parentKind: parentKind, state: state)
    }
}
