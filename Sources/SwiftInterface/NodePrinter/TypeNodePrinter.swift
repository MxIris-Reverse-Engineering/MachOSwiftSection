import Foundation
import Demangling
import Semantic

struct TypeNodePrinter: InterfaceNodePrintable {
    typealias Context = InterfaceNodePrinterContext

    var target: SemanticString = ""

    var targetNode: Node? { nil }

    var isProtocol: Bool { false }

    private(set) weak var delegate: (any NodePrintableDelegate)?

    init(delegate: (any NodePrintableDelegate)? = nil) {
        self.delegate = delegate
    }

    mutating func printRoot(_ node: Node) throws -> SemanticString {
        printName(node)
        return target
    }
}
