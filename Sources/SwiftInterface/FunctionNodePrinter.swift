import Foundation
import Demangle
import MachOExtensions

struct FunctionNodePrinter: InterfaceNodePrinter {
    private var target: String = ""

    enum Error: Swift.Error {
        case onlySupportedForFunctionNode
    }

    mutating func write(_ content: String) {
        target.write(content)
    }

    mutating func printRoot(_ node: Node) throws -> String {
        guard node.kind == .function || node.kind == .boundGenericFunction else { throw Error.onlySupportedForFunctionNode }
        printFunction(node)
        return target
    }

    private mutating func printFunction(_ name: Node) {
        var genericFunctionTypeList: Node?
        var name = name
        if name.kind == .boundGenericFunction, let first = name.children.at(0), let second = name.children.at(1) {
            name = first
            genericFunctionTypeList = second
        }
        guard var type = name.children.first(where: { $0.kind == .type }) else { return }
        if type.kind != .type {
            guard let nextType = name.children.at(2) else { return }
            type = nextType
        }
        guard type.kind == .type, let firstChild = type.children.first else { return }
        type = firstChild

        var t = type
        while t.kind == .dependentGenericType, let next = t.children.at(1)?.children.at(0) {
            t = next
        }
//            switch t.kind {
//            case .functionType,
//                 .noEscapeFunctionType,
//                 .uncurriedFunctionType,
//                 .cFunctionPointer,
//                 .thinFunctionType: break
//            default: typePr = .withColon
//            }

        printEntityType(name: name, type: type, genericFunctionTypeList: genericFunctionTypeList)
    }

    mutating func printName(_ node: Node) -> Node? {
        return nil
    }

    private mutating func printEntityType(name: Node, type: Node, genericFunctionTypeList: Node?) {
        let labelList = name.children.first(where: { $0.kind == .labelList })
        if let gftl = genericFunctionTypeList {
            printChildren(gftl, prefix: "<", suffix: ">", separator: ", ")
        }
        var t = type
        if type.kind == .dependentGenericType {
            if genericFunctionTypeList == nil {
                _ = printOptional(type.children.first)
            }
            if let dt = type.children.at(1) {
                if dt.needSpaceBeforeType {
                    target.write(" ")
                }
                if let first = dt.children.first {
                    t = first
                }
            }
        }
        printFunctionType(labelList: labelList, t)
    }

    private mutating func printFunctionType(labelList: Node? = nil, _ name: Node) {
        switch name.kind {
        case .autoClosureType,
             .escapingAutoClosureType: target.write("@autoclosure ")
        case .thinFunctionType: target.write("@convention(thin) ")
        case .cFunctionPointer:
            printConventionWithMangledCType(name, label: "c")
        case .escapingObjCBlock:
            target.write("@escaping ")
            fallthrough
        case .objCBlock:
            printConventionWithMangledCType(name, label: "block")
        default: break
        }

        let argIndex = name.children.count - 2
        var startIndex = 0
        var isSendable = false
        var isAsync = false
        var hasSendingResult = false
        var diffKind = UnicodeScalar(0)
        if name.children.at(startIndex)?.kind == .clangType {
            startIndex += 1
        }
        if name.children.at(startIndex)?.kind == .sendingResultFunctionType {
            startIndex += 1
            hasSendingResult = true
        }
        if name.children.at(startIndex)?.kind == .isolatedAnyFunctionType {
            _ = printOptional(name.children.at(startIndex))
            startIndex += 1
        }
        var nonIsolatedCallerNode: Node?
        if name.children.at(startIndex)?.kind == .nonIsolatedCallerFunctionType {
            nonIsolatedCallerNode = name.children.at(startIndex)
            startIndex += 1
        }
        if name.children.at(startIndex)?.kind == .globalActorFunctionType {
            _ = printOptional(name.children.at(startIndex))
            startIndex += 1
        }
        if name.children.at(startIndex)?.kind == .differentiableFunctionType {
            diffKind = UnicodeScalar(UInt8(name.children.at(startIndex)?.index ?? 0))
            startIndex += 1
        }
        var thrownErrorNode: Node?
        if name.children.at(startIndex)?.kind == .throwsAnnotation || name.children.at(startIndex)?.kind == .typedThrowsAnnotation {
            thrownErrorNode = name.children.at(startIndex)
            startIndex += 1
        }
        if name.children.at(startIndex)?.kind == .concurrentFunctionType {
            startIndex += 1
            isSendable = true
        }
        if name.children.at(startIndex)?.kind == .asyncAnnotation {
            startIndex += 1
            isAsync = true
        }

        switch diffKind {
        case "f": target.write("@differentiable(_forward) ")
        case "r": target.write("@differentiable(reverse) ")
        case "l": target.write("@differentiable(_linear) ")
        case "d": target.write("@differentiable ")
        default: break
        }

        if let nonIsolatedCallerNode {
            _ = printName(nonIsolatedCallerNode)
        }

        if isSendable {
            target.write("@Sendable ")
        }

        guard let parameterType = name.children.at(argIndex) else { return }
        printFunctionParameters(labelList: labelList, parameterType: parameterType, showTypes: true)
        if isAsync {
            target.write(" async")
        }
        if let thrownErrorNode {
            _ = printName(thrownErrorNode)
        }
        target.write(" -> ")
        if hasSendingResult {
            target.write("sending ")
        }

        _ = printOptional(name.children.at(argIndex + 1))
    }

    private mutating func printFunctionParameters(labelList: Node?, parameterType: Node, showTypes: Bool) {
        guard parameterType.kind == .argumentTuple else { return }
        guard let t = parameterType.children.first, t.kind == .type else { return }
        guard let parameters = t.children.first else { return }

        if parameters.kind != .tuple {
            if showTypes {
                target.write("(")
                _ = printName(parameters)
                target.write(")")
            } else {
                target.write("(_:)")
            }
            return
        }

        target.write("(")
        for tuple in parameters.children.enumerated() {
            if let label = labelList?.children.at(tuple.offset) {
                target.write(label.kind == .identifier ? (label.text ?? "") : "_", context: .context(for: parameterType, state: .printFunctionParameters))
                target.write(":")
                if showTypes {
                    target.write(" ")
                }
            } else if !showTypes {
                if let label = tuple.element.children.first(where: { $0.kind == .tupleElementName }) {
                    target.write(label.text ?? "", context: .context(for: parameterType, state: .printFunctionParameters))
                    target.write(":")
                } else {
                    target.write("_", context: .context(for: parameterType, state: .printFunctionParameters))
                    target.write(":")
                }
            }

            if showTypes {
                _ = printName(tuple.element)
                if tuple.offset != parameters.children.count - 1 {
                    target.write(", ")
                }
            }
        }
        target.write(")")
    }

    private mutating func printConventionWithMangledCType(_ name: Node, label: String) {
        target.write("@convention(\(label)")
        if let firstChild = name.children.first, firstChild.kind == .clangType {
            target.write(", mangledCType: \"")
            _ = printName(firstChild)
            target.write("\"")
        }
        target.write(") ")
    }
}
