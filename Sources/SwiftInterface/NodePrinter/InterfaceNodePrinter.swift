import Demangle
import Semantic

protocol InterfaceNodePrinter: BoundGenericNodePrintable, TypeNodePrintable, DependentGenericNodePrintable, FunctionTypeNodePrintable {
    mutating func printRoot(_ node: Node) throws -> SemanticString
}
