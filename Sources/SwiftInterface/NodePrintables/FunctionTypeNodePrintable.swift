import Demangle

protocol FunctionTypeNodePrintable: NodePrintable {
    mutating func printNameInFunction(_ name: Node) -> Bool
    mutating func printFunctionType(_ functionType: Node, labelList: Node?, isAllocator: Bool, isBlockOrClosure: Bool)
}

extension FunctionTypeNodePrintable {
    mutating func printNameInFunction(_ name: Node) -> Bool {
        switch name.kind {
        case .returnType:
            printReturnType(name)
        case .tupleElement:
            printTupleElement(name)
        case .cFunctionPointer,
             .objCBlock,
             .noEscapeFunctionType,
             .escapingAutoClosureType,
             .autoClosureType,
             .thinFunctionType,
             .functionType,
             .escapingObjCBlock,
             .uncurriedFunctionType:
            printFunctionType(name, labelList: nil, isAllocator: false, isBlockOrClosure: true)
        default:
            return false
        }
        return true
    }

    mutating func printFunctionType(_ functionType: Node, labelList: Node?, isAllocator: Bool, isBlockOrClosure: Bool) {
        switch functionType.kind {
        case .autoClosureType,
             .escapingAutoClosureType: target.write("@autoclosure ")
        case .thinFunctionType: target.write("@convention(thin) ")
        case .cFunctionPointer:
            printConventionWithMangledCType(functionType, label: "c")
        case .escapingObjCBlock:
            target.write("@escaping ")
            fallthrough
        case .objCBlock:
            printConventionWithMangledCType(functionType, label: "block")
        default: break
        }

        let argIndex = functionType.children.count - 2
        var startIndex = 0
        var isSendable = false
        var isAsync = false
        var hasSendingResult = false
        var diffKind = UnicodeScalar(0)
        if functionType.children.at(startIndex)?.kind == .clangType {
            startIndex += 1
        }
        if functionType.children.at(startIndex)?.kind == .sendingResultFunctionType {
            startIndex += 1
            hasSendingResult = true
        }
        if functionType.children.at(startIndex)?.kind == .isolatedAnyFunctionType {
            _ = printOptional(functionType.children.at(startIndex))
            startIndex += 1
        }
        var nonIsolatedCallerNode: Node?
        if functionType.children.at(startIndex)?.kind == .nonIsolatedCallerFunctionType {
            nonIsolatedCallerNode = functionType.children.at(startIndex)
            startIndex += 1
        }
        if functionType.children.at(startIndex)?.kind == .globalActorFunctionType {
            _ = printOptional(functionType.children.at(startIndex))
            startIndex += 1
        }
        if functionType.children.at(startIndex)?.kind == .differentiableFunctionType {
            diffKind = UnicodeScalar(UInt8(functionType.children.at(startIndex)?.index ?? 0))
            startIndex += 1
        }
        var thrownErrorNode: Node?
        if functionType.children.at(startIndex)?.kind == .throwsAnnotation || functionType.children.at(startIndex)?.kind == .typedThrowsAnnotation {
            thrownErrorNode = functionType.children.at(startIndex)
            startIndex += 1
        }
        if functionType.children.at(startIndex)?.kind == .concurrentFunctionType {
            startIndex += 1
            isSendable = true
        }
        if functionType.children.at(startIndex)?.kind == .asyncAnnotation {
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

        guard let parameterType = functionType.children.at(argIndex) else { return }

        printFunctionParameters(labelList: labelList, parameterType: parameterType, showTypes: true)

        if isAsync {
            target.write(" async")
        }
        if let thrownErrorNode {
            _ = printName(thrownErrorNode)
        }

        let returnType = functionType.children.at(argIndex + 1)

        if !isBlockOrClosure, let typeNode = returnType?.children.first, typeNode.kind == .type, let tuple = typeNode.children.first, tuple.kind == .tuple, tuple.children.isEmpty {
            return
        } else if isAllocator {
            return
        }

        target.write(" -> ")

        if hasSendingResult {
            target.write("sending ")
        }

        printOptional(returnType)
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

    private mutating func printTupleElement(_ name: Node) {
        if let label = name.children.first(where: { $0.kind == .tupleElementName }) {
            target.write("\(label.text ?? ""): ")
        }
        guard let type = name.children.first(where: { $0.kind == .type }) else { return }
        _ = printName(type)
        if let _ = name.children.first(where: { $0.kind == .variadicMarker }) {
            target.write("...")
        }
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

    private mutating func printReturnType(_ name: Node) {
        if name.children.isEmpty, let t = name.text {
            target.write(t)
        } else {
            printChildren(name)
        }
    }
}
