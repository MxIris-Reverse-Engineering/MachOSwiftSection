import Demangle
import Semantic

protocol InterfaceNodePrinter: BoundGenericNodePrintable, TypeNodePrintable, DependentGenericNodePrintable, FunctionTypeNodePrintable {
    mutating func printRoot(_ node: Node) throws -> SemanticString
}

extension InterfaceNodePrinter {
    mutating func printName(_ name: Node, asPrefixContext: Bool) -> Node? {
        if printNameInBase(name) {
            return nil
        }
        if printNameInBoundGeneric(name) {
            return nil
        }
        if printNameInType(name) {
            return nil
        }
        if printNameInDependentGeneric(name) {
            return nil
        }
        if printNameInFunction(name) {
            return nil
        }
        return nil
    }
}
