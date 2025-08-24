import Foundation
import Demangle
import MachOExtensions
import Semantic

struct FunctionNodePrinter: InterfaceNodePrinter, BoundGenericNodePrintable, TypeNodePrintable, DependentGenericNodePrintable, FunctionTypeNodePrintable {
    var target: SemanticString = ""

    enum Error: Swift.Error {
        case onlySupportedForFunctionNode
    }

    mutating func printRoot(_ node: Node) throws -> SemanticString {
        try _printRoot(node)
        return target
    }

    private mutating func _printRoot(_ node: Node) throws {
        if node.kind == .global, let first = node.children.first {
            if first.kind == .asyncFunctionPointer, let second = node.children.second {
                try _printRoot(second)
            } else {
                try _printRoot(first)
            }
        } else if node.kind == .function || node.kind == .boundGenericFunction || node.kind == .allocator {
            printFunction(node)
        } else if node.kind == .static, let first = node.children.first {
            target.write("static ")
            try _printRoot(first)
        } else if node.kind == .methodDescriptor, let first = node.children.first {
            try _printRoot(first)
        } else if node.kind == .protocolWitness, let second = node.children.second {
            try _printRoot(second)
        } else {
            throw Error.onlySupportedForFunctionNode
        }
    }

    private mutating func printFunction(_ name: Node) {
        var genericFunctionTypeList: Node?
        var name = name
        if name.kind == .boundGenericFunction, let first = name.children.at(0), let second = name.children.at(1) {
            name = first
            genericFunctionTypeList = second
        }
        if name.kind != .allocator {
            target.write("func ")
            if let identifier = name.children.first(of: .identifier) {
                printIdentifier(identifier)
            } else if let privateDeclName = name.children.first(of: .privateDeclName) {
                printPrivateDeclName(privateDeclName)
            } else if let `operator` = name.children.first(of: .prefixOperator, .infixOperator, .postfixOperator), let text = `operator`.text {
                target.write(text + " ")
            }
        } else if name.kind == .allocator {
            target.write("init")
        }
        if let type = name.children.first(of: .type), let functionType = type.children.first {
            printLabelList(name: name, type: functionType, genericFunctionTypeList: genericFunctionTypeList)
        }
        
        if let genericSignature = name.first(of: .dependentGenericSignature) {
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

    private mutating func printLabelList(name: Node, type: Node, genericFunctionTypeList: Node?) {
        let labelList = name.children.first(of: .labelList)
        if labelList != nil || genericFunctionTypeList != nil {
            if let genericFunctionTypeList {
                printChildren(genericFunctionTypeList, prefix: "<", suffix: ">", separator: ", ")
            }
            var functionType = type
            if type.kind == .dependentGenericType {
                if genericFunctionTypeList == nil {
                    printOptional(type.children.first)
                }
                if let dt = type.children.at(1) {
                    if dt.needSpaceBeforeType {
                        target.write(" ")
                    }
                    if let first = dt.children.first {
                        functionType = first
                    }
                }
            }
            printFunctionType(functionType, labelList: labelList, isAllocator: name.kind == .allocator, isBlockOrClosure: false)
        } else {
            printFunctionType(type, labelList: labelList, isAllocator: name.kind == .allocator, isBlockOrClosure: false)
        }
    }
}
