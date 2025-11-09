import Foundation
import Demangling
import Semantic

struct TypeNodePrinter: InterfaceNodePrintable {
    typealias Context = InterfaceNodePrinterContext

    var target: SemanticString = ""

    var targetNode: Node? { nil }

    private(set) var isProtocol: Bool

    private(set) weak var delegate: (any NodePrintableDelegate)?

    init(delegate: (any NodePrintableDelegate)? = nil, isProtocol: Bool = false) {
        self.delegate = delegate
        self.isProtocol = isProtocol
    }

    mutating func printRoot(_ node: Node) async throws -> SemanticString {
        await printName(node)
        return target
    }
}
