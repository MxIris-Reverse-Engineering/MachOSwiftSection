import Foundation
import Demangling
import Semantic

struct VariableNodePrinter: InterfaceNodePrintable {
    typealias Context = InterfaceNodePrinterContext
    
    var target: SemanticString = ""

    private var isStatic: Bool = false

    private let isStored: Bool
    
    private let isOverride: Bool

    private let hasSetter: Bool

    private let indentation: Int

    private(set) weak var delegate: (any NodePrintableDelegate)?

    private(set) var targetNode: Node?
    
    private(set) var isProtocol: Bool = false
    
    init(isStored: Bool, isOverride: Bool, hasSetter: Bool, indentation: Int, delegate: (any NodePrintableDelegate)? = nil) {
        self.isStored = isStored
        self.isOverride = isOverride
        self.hasSetter = hasSetter
        self.indentation = indentation
        self.delegate = delegate
    }

    enum Error: Swift.Error {
        case onlySupportedForVariableNode(Node)
    }

    mutating func printRoot(_ node: Node) throws -> SemanticString {
        if isOverride {
            target.write("override", context: .context(for: node, state: .printKeyword))
            target.writeSpace()
        }
        try _printRoot(node)
        return target
    }

    private mutating func _printRoot(_ node: Node) throws {
        if node.kind == .global, let first = node.children.first {
            if first.isKind(of: .asyncFunctionPointer, .mergedFunction), let second = node.children.second {
                try _printRoot(second)
            } else {
                try _printRoot(first)
            }
        } else if node.kind == .variable {
            try printVariable(node)
        } else if node.kind == .static, let first = node.children.first {
            target.write("static ")
            isStatic = true
            try _printRoot(first)
        } else if node.kind == .methodDescriptor, let first = node.children.first {
            try _printRoot(first)
        } else if node.kind == .protocolWitness, let second = node.children.second {
            try _printRoot(second)
        } else if node.kind == .getter || node.kind == .setter, let first = node.children.first {
            try _printRoot(first)
        } else {
            throw Error.onlySupportedForVariableNode(node)
        }
    }

    private mutating func printVariable(_ node: Node) throws {
        let identifier: Node? = if let identifier = node.children.first(of: .identifier) {
            identifier
        } else if let privateDeclName = node.children.first(of: .privateDeclName) {
            privateDeclName.children.at(1)
        } else {
            nil
        }
        guard let identifier else {
            throw Error.onlySupportedForVariableNode(node)
        }
        
        var targetNode = node
        if isStatic {
            targetNode = Node(kind: .static, child: targetNode)
        }
        self.targetNode = targetNode
        
        if let first = node.children.first {
            if first.isKind(of: .extension) {
                isProtocol = first.children.at(1)?.isKind(of: .protocol) ?? false
            } else if first.isKind(of: .protocol) {
                isProtocol = true
            }
        }
        if isStored, !hasSetter {
            target.write("let ")
        } else {
            target.write("var ")
        }

        target.write(identifier.text ?? "", context: .context(for: identifier, state: .printIdentifier))
        target.write(": ")
        
        guard let type = node.children.first(of: .type) else { return }
        
        printName(type)
        
        guard !isStored else { return }

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
