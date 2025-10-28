import Foundation
import Demangling
import Semantic

extension SemanticString: NodePrinterTarget {
    package mutating func write(_ content: String, context: NodePrintContext?) {
        guard let context else {
            write(content)
            return
        }
        switch context.state {
        case .printFunctionParameters:
            write(content, type: .function(.declaration))
        case .printIdentifier:
            let semanticType: SemanticType
            switch context.node?.parent?.kind {
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
        case .printKeyword:
            write(content, type: .keyword)
        case .printType:
            write(content, type: .type(.other, .name))
        }
    }
}

extension Node {
    public func printSemantic(using options: DemangleOptions = .default) -> SemanticString {
        var printer = NodePrinter<SemanticString>(options: options)
        return printer.printRoot(self)
    }
}

extension Node {
    package var hasWeakNode: Bool {
        preorder().first { $0.kind == .weak } != nil
    }
}
