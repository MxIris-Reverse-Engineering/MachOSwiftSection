package struct NodePrintContext {
    package let node: Node
    package let state: NodePrintState

    package static func context(for node: Node, state: NodePrintState) -> NodePrintContext {
        NodePrintContext(node: node, state: state)
    }
}
