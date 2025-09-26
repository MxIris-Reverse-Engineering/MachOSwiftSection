import Foundation
import Demangle
import MachOExtensions
import Semantic

struct FunctionNodePrinter: InterfaceNodePrinter {
    var target: SemanticString = ""
    
    var isStatic: Bool = false
    
    weak var delegate: (any InterfaceNodePrinterDelegate)?

    init(delegate: (any InterfaceNodePrinterDelegate)? = nil) {
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

    private mutating func printFunction(_ node: Node) {
        var genericFunctionTypeList: Node?
        var node = node
        if node.kind == .boundGenericFunction, let first = node.children.at(0), let second = node.children.at(1) {
            node = first
            genericFunctionTypeList = second
        }
        if node.kind != .allocator {
            target.write("func ")
            if let identifier = node.children.first(of: .identifier) {
                printIdentifier(identifier)
            } else if let privateDeclName = node.children.first(of: .privateDeclName) {
                printPrivateDeclName(privateDeclName)
            } else if let `operator` = node.children.first(of: .prefixOperator, .infixOperator, .postfixOperator), let text = `operator`.text {
                target.write(text + " ")
            }
        } else if node.kind == .allocator {
            target.write("init")
        }
        if let type = node.children.first(of: .type), let functionType = type.children.first {
            printLabelList(name: node, type: functionType, genericFunctionTypeList: genericFunctionTypeList)
        }

        if node.first(of: .opaqueReturnType) != nil {
            var opaqueReturnTypeOf = node
            if isStatic {
                opaqueReturnTypeOf = Node(kind: .static, child: opaqueReturnTypeOf)
            }
            if let opaqueType = delegate?.opaqueType(forNode: opaqueReturnTypeOf) {
                target.writeSpace()
                target.write(opaqueType)
            }
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
    }
}
