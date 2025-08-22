import Demangle
import Semantic

protocol InterfaceNodePrinter {
    mutating func printRoot(_ node: Node) throws -> SemanticString
}
