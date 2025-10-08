import Foundation
import Demangle
import Semantic

struct SubscriptNodePrinter: InterfaceNodePrintable {
    typealias Context = InterfaceNodePrinterContext
    
    var target: SemanticString = ""

    private var isStatic: Bool = false

    private let isOverride: Bool
    
    private let hasSetter: Bool

    private let indentation: Int

    private(set) weak var delegate: (any NodePrintableDelegate)?

    private(set) var isProtocol: Bool = false

    private(set) var targetNode: Node?
    
    init(isOverride: Bool, hasSetter: Bool, indentation: Int, delegate: (any NodePrintableDelegate)? = nil) {
        self.isOverride = isOverride
        self.hasSetter = hasSetter
        self.indentation = indentation
        self.delegate = delegate
    }

    enum Error: Swift.Error {
        case onlySupportedForSubscriptNode(Node)
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
        } else if node.isKind(of: .subscript) {
            printSubscript(node)
        } else if node.kind == .static, let first = node.children.first {
            target.write("static ")
            isStatic = true
            try _printRoot(first)
        } else if node.kind == .methodDescriptor, let first = node.children.first {
            try _printRoot(first)
        } else if node.kind == .getter || node.kind == .setter, let first = node.children.first {
            try _printRoot(first)
        } else if node.kind == .protocolWitness, let second = node.children.second {
            try _printRoot(second)
        } else {
            throw Error.onlySupportedForSubscriptNode(node)
        }
    }

    private mutating func printSubscript(_ node: Node) {
        // Setup target node for opaque return type lookup
        var targetNode = node
        if isStatic {
            targetNode = Node(kind: .static, child: targetNode)
        }
        self.targetNode = targetNode
        
        var genericFunctionTypeList: Node?
        var node = node
        if node.kind == .boundGenericFunction, let first = node.children.at(0), let second = node.children.at(1) {
            node = first
            genericFunctionTypeList = second
        }
        target.write("subscript")
        if let first = node.children.first {
            if first.isKind(of: .extension) {
                isProtocol = first.children.at(1)?.isKind(of: .protocol) ?? false
            } else if first.isKind(of: .protocol) {
                isProtocol = true
            }
        }
        if node.children.at(1)?.isKind(of: .labelList) == false {
            node.insertChild(Node(kind: .labelList), at: 1)
        }

        if let type = node.children.first(of: .type), let functionType = type.children.first {
            printLabelList(name: node, type: functionType, genericFunctionTypeList: genericFunctionTypeList)
        }
        if let genericSignature = node.first(of: .dependentGenericSignature) {
            let nodes = genericSignature.all(of: .requirementKinds)
            for (offset, node) in nodes.offsetEnumerated() {
                if offset.isStart {
                    target.write(" where ")
                }
                printName(node)
                if !offset.isEnd {
                    target.write(", ")
                }
            }
        }

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
