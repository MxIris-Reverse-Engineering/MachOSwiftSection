import SwiftDeclaration
import Foundation
import Demangling
import Semantic

struct TypeNodePrinter: InterfaceNodePrintable {
    typealias Context = InterfaceNodePrinterContext<SemanticString>

    var target: SemanticString = ""

    var context = Context()

    private(set) weak var delegate: (any NodePrintableDelegate)?

    init(delegate: (any NodePrintableDelegate)? = nil, isProtocol: Bool = false) {
        self.delegate = delegate
        context.isProtocol = isProtocol
    }

    mutating func printRoot(_ node: Node) async throws -> SemanticString {
        await printName(node)
        return target
    }
}
