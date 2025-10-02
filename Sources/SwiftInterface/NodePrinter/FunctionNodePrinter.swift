import Foundation
import Demangle
import MachOExtensions
import Semantic

struct FunctionNodePrinter: InterfaceNodePrintable {
    typealias Context = InterfaceNodePrinterContext
    
    var target: SemanticString = ""

    private var isStatic: Bool = false

    private(set) weak var delegate: (any NodePrintableDelegate)?

    private(set) var isProtocol: Bool = false

    private(set) var targetNode: Node?

    init(delegate: (any NodePrintableDelegate)? = nil) {
        self.delegate = delegate
    }

    enum Error: Swift.Error {
        case onlySupportedForFunctionNode(Node)
    }

    mutating func printRoot(_ node: Node) throws -> SemanticString {
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
        } else if node.isKind(of: .function, .boundGenericFunction, .allocator, .constructor) {
            printFunction(node)
        } else if node.kind == .static, let first = node.children.first {
            target.write("static ")
            isStatic = true
            try _printRoot(first)
        } else if node.kind == .methodDescriptor, let first = node.children.first {
            try _printRoot(first)
        } else if node.kind == .protocolWitness, let second = node.children.second {
            try _printRoot(second)
        } else {
            throw Error.onlySupportedForFunctionNode(node)
        }
    }

    private mutating func printFunction(_ function: Node) {
        var targetNode = function
        if isStatic {
            targetNode = Node(kind: .static, child: targetNode)
        }
        self.targetNode = targetNode

        var genericFunctionTypeList: Node?
        var function = function
        if function.kind == .boundGenericFunction, let first = function.children.at(0), let second = function.children.at(1) {
            function = first
            genericFunctionTypeList = second
        }
        if let first = function.children.first {
            if first.isKind(of: .extension) {
                isProtocol = first.children.at(1)?.isKind(of: .protocol) ?? false
            } else if first.isKind(of: .protocol) {
                isProtocol = true
            }
        }
        if function.kind != .allocator {
            target.write("func ")
            if let identifier = function.children.first(of: .identifier) {
                printIdentifier(identifier)
            } else if let privateDeclName = function.children.first(of: .privateDeclName) {
                printPrivateDeclName(privateDeclName)
            } else if let `operator` = function.children.first(of: .prefixOperator, .infixOperator, .postfixOperator), let text = `operator`.text {
                target.write(text + " ")
            }
        } else if function.kind == .allocator {
            target.write("init")
            if function.isReturnOptional {
                target.write("?")
            }
        }
        if let type = function.children.first(of: .type), let functionType = type.children.first {
            printLabelList(name: function, type: functionType, genericFunctionTypeList: genericFunctionTypeList)
        }

        if let genericSignature = function.first(of: .dependentGenericSignature) {
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
    }
}

extension Node {
    var isReturnOptional: Bool {
        if let returnType = first(of: .returnType), let type = returnType.children.first, let boundGenericEnum = type.children.first, boundGenericEnum.isKind(of: .boundGenericEnum), let first = boundGenericEnum.children.first?.children.first {
            return first == Node(kind: .enum) {
                Node(kind: .module, contents: .text("Swift"))
                Node(kind: .identifier, contents: .text("Optional"))
            }
        } else {
            return false
        }
    }
}
