import Foundation
import Demangle
import Semantic

extension SemanticString: NodePrinterTarget {
    package mutating func write(_ content: String, context: NodePrintContext) {
        switch context.state {
        case .printFunctionParameters:
            write(content, type: .function(.declaration))
        case .printIdentifier:
            let semanticType: SemanticType
            switch context.node.parent?.kind {
            case .function:
                semanticType = .function(.declaration)
            case .variable:
                semanticType = .variable
            case .enum:
                semanticType = .type(.enum, .name)
            case .structure:
                semanticType = .type(.struct, .name)
            case .class:
                semanticType = .type(.class, .name)
            case .protocol:
                semanticType = .type(.protocol, .name)
            default:
                semanticType = .standard
            }
            write(content, type: semanticType)
        case .printModule:
            write(content, type: .other)
        }
    }
}

extension Node {
    public func printSemantic(using options: DemangleOptions = .default) -> SemanticString {
        var printer = NodePrinter<SemanticString>(options: options)
        return printer.printRoot(self)
    }
}
