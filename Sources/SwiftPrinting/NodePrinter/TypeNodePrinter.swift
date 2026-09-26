import SwiftDeclaration
import Foundation
import Demangling
import Semantic

typealias SemanticTypeNodePrinter = TypeNodePrinter<SemanticString>

struct TypeNodePrinter<Target: NodePrinterTarget>: InterfaceNodePrintable {
    typealias Context = InterfaceNodePrinterContext<Target>

    var target = Target()

    var context = Context()

    private(set) weak var delegate: (any NodePrintableDelegate)?

    init(delegate: (any NodePrintableDelegate)? = nil, isProtocol: Bool = false) {
        self.delegate = delegate
        context.isProtocol = isProtocol
    }

    mutating func printRoot(_ node: Node) async throws -> Target {
        await printName(node)
        return target
    }
}
