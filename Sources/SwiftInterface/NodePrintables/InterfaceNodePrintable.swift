import Demangling
import Semantic
import MemberwiseInit

protocol InterfaceNodePrintable: NodePrintable, BoundGenericNodePrintable, TypeNodePrintable, DependentGenericNodePrintable, FunctionTypeNodePrintable {
    mutating func printRoot(_ node: Node) async throws -> SemanticString
}

protocol InterfaceNodePrintableContext: NodePrintableContext, FunctionTypeNodePrintableContext {}

@MemberwiseInit()
struct InterfaceNodePrinterContext: InterfaceNodePrintableContext {
    var isAllocator: Bool = false
    
    var isBlockOrClosure: Bool = false
    
    init() {}
}

extension InterfaceNodePrintable {
    mutating func printName(_ name: Node, asPrefixContext: Bool, context: Context?) async -> Node? {
        if await printNameInBase(name, context: context) {
            return nil
        }
        if await printNameInBoundGeneric(name, context: context) {
            return nil
        }
        if await printNameInType(name, context: context) {
            return nil
        }
        if await printNameInDependentGeneric(name, context: context) {
            return nil
        }
        if await printNameInFunction(name, context: context) {
            return nil
        }
        return nil
    }
}
