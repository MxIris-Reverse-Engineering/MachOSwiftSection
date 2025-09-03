import Foundation
import Demangle
import Semantic

struct VariableNodePrinter: InterfaceNodePrinter {
    var target: SemanticString = ""

    let hasSetter: Bool
    
    let indentation: Int

    let cImportedInfoProvider: (any CImportedInfoProvider)?

    init(hasSetter: Bool, indentation: Int, cImportedInfoProvider: (any CImportedInfoProvider)? = nil) {
        self.hasSetter = hasSetter
        self.indentation = indentation
        self.cImportedInfoProvider = cImportedInfoProvider
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
            try printVariable(node)
        } else if node.kind == .static, let first = node.children.first {
            target.write("static ")
            try _printRoot(first)
        } else if node.kind == .protocolWitness, let second = node.children.second {
            try _printRoot(second)
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

    private mutating func printVariable(_ name: Node) throws {
        let identifier: Node? = if let identifier = name.children.first(of: .identifier) {
            identifier
        } else if let privateDeclName = name.children.first(of: .privateDeclName) {
            privateDeclName.children.at(1)
        } else {
            nil
        }
        guard let identifier else {
            throw Error.onlySupportedForVariableNode
        }
        target.write("var ")
        target.write(identifier.text ?? "", context: .context(for: identifier, state: .printIdentifier))
        target.write(": ")
        guard let type = name.children.first(of: .type) else { return }
        printName(type)

        target.write(" {")
        target.write("\n")
        target.write(String(repeating: " ", count: (indentation + 1) * 4))
        target.write("get")
        if hasSetter {
            target.write("\n")
            target.write(String(repeating: " ", count: (indentation + 1) * 4))
            target.write("set")
        }
        target.write("\n")
        target.write(String(repeating: " ", count: indentation * 4))
        target.write("}")
    }
}
