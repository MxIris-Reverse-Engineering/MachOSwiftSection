import Foundation
import Demangling
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

    mutating func printRoot(_ node: Node) async throws -> SemanticString {
        if isOverride {
            target.write("override", context: .context(state: .printKeyword))
            target.writeSpace()
        }
        try await _printRoot(node)
        return target
    }

    private mutating func _printRoot(_ node: Node) async throws {
        if node.kind == .global, let first = node.children.first {
            if needsSkipFirstNodeKinds.contains(first.kind), let second = node.children.second {
                try await _printRoot(second)
            } else {
                try await _printRoot(first)
            }
        } else if node.isKind(of: .subscript) {
            await printSubscript(node)
        } else if node.kind == .static, let first = node.children.first {
            target.write("static", context: .context(state: .printKeyword))
            target.writeSpace()
            isStatic = true
            try await _printRoot(first)
        } else if node.kind == .methodDescriptor, let first = node.children.first {
            try await _printRoot(first)
        } else if node.kind == .getter || node.kind == .setter, let first = node.children.first {
            try await _printRoot(first)
        } else if node.kind == .protocolWitness, let second = node.children.second {
            try await _printRoot(second)
        } else {
            throw Error.onlySupportedForSubscriptNode(node)
        }
    }

    private mutating func printSubscript(_ node: Node) async {
        // Setup target node for opaque return type lookup
        var targetNode = node
        if isStatic {
            targetNode = Node.create(kind: .static, child: targetNode)
        }
        self.targetNode = targetNode

        var genericFunctionTypeList: Node?
        var node = node
        if node.kind == .boundGenericFunction, let first = node.children.at(0), let second = node.children.at(1) {
            node = first
            genericFunctionTypeList = second
        }
        target.write("subscript", context: .context(state: .printKeyword))
        if let first = node.children.first {
            if first.isKind(of: .extension) {
                isProtocol = first.children.at(1)?.isKind(of: .protocol) ?? false
            } else if first.isKind(of: .protocol) {
                isProtocol = true
            }
        }
        if node.children.at(1)?.isKind(of: .labelList) == false {
            node = NodeBuilder(node).insertingChild(Node.create(kind: .labelList), at: 1)
        }

        if let type = node.children.first(of: .type), let functionType = type.children.first {
            await printLabelList(name: node, type: functionType, genericFunctionTypeList: genericFunctionTypeList)
        }
        if let genericSignature = node.first(of: .dependentGenericSignature) {
            let nodes = genericSignature.all(of: .requirementKinds)
            for (offset, node) in nodes.offsetEnumerated() {
                if offset.isStart {
                    target.writeSpace()
                    target.write("where", context: .context(state: .printKeyword))
                    target.writeSpace()
                }
                await printName(node)
                if !offset.isEnd {
                    target.write(", ")
                }
            }
        }

        target.write(" {")
        target.write("\n")
        target.write(String(repeating: " ", count: (indentation + 1) * 4))
        target.write("get", context: .context(state: .printKeyword))
        if hasSetter {
            target.write("\n")
            target.write(String(repeating: " ", count: (indentation + 1) * 4))
            target.write("set", context: .context(state: .printKeyword))
        }
        target.write("\n")
        target.write(String(repeating: " ", count: indentation * 4))
        target.write("}")
    }
}
