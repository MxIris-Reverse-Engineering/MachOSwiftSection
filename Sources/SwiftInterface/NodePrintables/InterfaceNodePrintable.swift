import Demangle
import Semantic
import MemberwiseInit

protocol InterfaceNodePrintable: NodePrintable, BoundGenericNodePrintable, TypeNodePrintable, DependentGenericNodePrintable, FunctionTypeNodePrintable {
    mutating func printRoot(_ node: Node) throws -> SemanticString
}

protocol InterfaceNodePrintableContext: NodePrintableContext, FunctionTypeNodePrintableContext {}

@MemberwiseInit()
struct InterfaceNodePrinterContext: InterfaceNodePrintableContext {
    var isAllocator: Bool = false
    
    var isBlockOrClosure: Bool = false
    
    init() {}
}

extension InterfaceNodePrintable {
    mutating func printName(_ name: Node, asPrefixContext: Bool, context: Context?) -> Node? {
        if printNameInBase(name, context: context) {
            return nil
        }
        if printNameInBoundGeneric(name, context: context) {
            return nil
        }
        if printNameInType(name, context: context) {
            return nil
        }
        if printNameInDependentGeneric(name, context: context) {
            return nil
        }
        if printNameInFunction(name, context: context) {
            return nil
        }
        return nil
    }
}
