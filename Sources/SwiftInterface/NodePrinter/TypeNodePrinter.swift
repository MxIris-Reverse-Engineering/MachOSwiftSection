import Foundation
import Demangle
import Semantic

struct TypeNodePrinter: InterfaceNodePrinter {
    var target: SemanticString = ""

    weak var delegate: (any InterfaceNodePrinterDelegate)?

    let isProtocol: Bool = false
    
    init(delegate: (any InterfaceNodePrinterDelegate)? = nil) {
        self.delegate = delegate
    }

    mutating func printRoot(_ node: Node) throws -> SemanticString {
        printName(node)
        return target
    }
}
