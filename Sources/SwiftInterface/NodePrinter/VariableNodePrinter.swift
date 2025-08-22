import Foundation
import Demangle
import Semantic

struct VariableNodePrinter: InterfaceNodePrinter, BoundGenericNodePrintable, TypeNodePrintable, DependentGenericNodePrintable, FunctionTypeNodePrintable {
    let hasSetter: Bool

    var target: SemanticString = ""

    init(hasSetter: Bool) {
        self.hasSetter = hasSetter
    }

    enum Error: Swift.Error {
        case onlySupportedForVariableNode
    }

    mutating func printRoot(_ node: Node) throws -> SemanticString {
        try _printRoot(node)
        return target
    }

    private mutating func _printRoot(_ node: Node) throws {
        if node.kind == .global, let first = node.children.first {
            try _printRoot(first)
        } else if node.kind == .variable {
            printVariable(node)
        } else if node.kind == .static, let first = node.children.first {
            target.write("static ")
            try _printRoot(first)
        } else if node.kind == .protocolWitness, let setterOrGetter = node.children.first(of: .setter, .getter) {
            try _printRoot(setterOrGetter)
        } else if node.kind == .getter || node.kind == .setter, let first = node.children.first {
            try _printRoot(first)
        } else {
            throw Error.onlySupportedForVariableNode
        }
    }

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

    private mutating func printVariable(_ name: Node) {
        guard let identifier = name.children.first(of: .identifier) else { return }
        target.write("var ")
        target.write(identifier.text ?? "", context: .context(for: identifier, state: .printIdentifier))
        target.write(": ")
        guard let type = name.children.first(of: .type) else { return }
        printName(type)

        target.write(" { ")
        if hasSetter {
            target.write("set ")
        }
        target.write("get ")
        target.write("}")
    }
}
