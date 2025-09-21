import Foundation
import Demangle
import MachOExtensions
import Semantic

struct FunctionNodePrinter: InterfaceNodePrinter {
    var target: SemanticString = ""

    let cImportedInfoProvider: (any CImportedInfoProvider)?

    init(cImportedInfoProvider: (any CImportedInfoProvider)? = nil) {
        self.cImportedInfoProvider = cImportedInfoProvider
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
            try _printRoot(first)
        } else if node.kind == .methodDescriptor, let first = node.children.first {
            try _printRoot(first)
        } else if node.kind == .protocolWitness, let second = node.children.second {
            try _printRoot(second)
        } else {
            throw Error.onlySupportedForFunctionNode(node)
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
}
