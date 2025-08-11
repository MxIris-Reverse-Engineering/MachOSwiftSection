import Demangle

protocol InterfaceNodePrinter {
    mutating func printRoot(_ node: Node) throws -> String
}
