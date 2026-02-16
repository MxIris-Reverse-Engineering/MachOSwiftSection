import Demangling

protocol FunctionTypeNodePrintableContext {
    var isAllocator: Bool { set get }
    var isBlockOrClosure: Bool { set get }
    init()
}

protocol FunctionTypeNodePrintable: NodePrintable where Context: FunctionTypeNodePrintableContext {
    mutating func printNameInFunction(_ name: Node, context: Context?) async -> Bool
    mutating func printFunctionType(_ functionType: Node, labelList: Node?, isAllocator: Bool, isBlockOrClosure: Bool) async
}

extension FunctionTypeNodePrintable {
    mutating func printNameInFunction(_ name: Node, context: Context?) async -> Bool {
        switch name.kind {
        case .returnType:
            await printReturnType(name)
        case .tupleElement:
            await printTupleElement(name)
        case .cFunctionPointer,
             .objCBlock,
             .noEscapeFunctionType,
             .escapingAutoClosureType,
             .autoClosureType,
             .thinFunctionType,
             .functionType,
             .escapingObjCBlock,
             .uncurriedFunctionType:
            await printFunctionType(name, labelList: nil, isAllocator: context?.isAllocator ?? false, isBlockOrClosure: context?.isBlockOrClosure ?? true)
        case .throwsAnnotation:
            target.writeSpace()
            target.write("throws", context: .context(state: .printKeyword))
        case .asyncAnnotation:
            target.writeSpace()
            target.write("async", context: .context(state: .printKeyword))
        case .typedThrowsAnnotation:
            await printTypeThrowsAnnotation(name)
        case .concurrentFunctionType:
            target.write("@Sendable", context: .context(state: .printKeyword))
            target.writeSpace()
        case .globalActorFunctionType:
            await printGlobalActorFunctionType(name)
        case .differentiableFunctionType:
            await printDifferentiableFunctionType(name)
        case .nonIsolatedCallerFunctionType:
            target.write("nonisolated(nonsending)", context: .context(state: .printKeyword))
            target.writeSpace()
        case .isolatedAnyFunctionType:
            target.write("@isolated(any)", context: .context(state: .printKeyword))
            target.writeSpace()
        case .sending:
            await printFirstChild(name, prefix: "sending ", prefixContext: .context(state: .printKeyword))
        case .sendingResultFunctionType:
            target.write("sending", context: .context(state: .printKeyword))
            target.writeSpace()
        case .clangType:
            target.write(name.text ?? "")
        case .packElement:
            await printFirstChild(name, prefix: "each ", prefixContext: .context(state: .printKeyword))
        case .packElementLevel:
            break
        case .packExpansion:
            await printFirstChild(name, prefix: "repeat ", prefixContext: .context(state: .printKeyword))
        default:
            return false
        }
        return true
    }

    mutating func printFunctionType(_ functionType: Node, labelList: Node?, isAllocator: Bool, isBlockOrClosure: Bool) async {
        switch functionType.kind {
        case .autoClosureType,
             .escapingAutoClosureType:
            target.write("@autoclosure", context: .context(state: .printKeyword))
            target.writeSpace()
        case .thinFunctionType:
            target.write("@convention(thin)", context: .context(state: .printKeyword))
            target.writeSpace()
        case .cFunctionPointer:
            await printConventionWithMangledCType(functionType, label: "c")
        case .escapingObjCBlock:
            target.write("@escaping", context: .context(state: .printKeyword))
            target.writeSpace()
            fallthrough
        case .objCBlock:
            await printConventionWithMangledCType(functionType, label: "block")
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
            _ = await printOptional(functionType.children.at(startIndex))
            startIndex += 1
        }
        var nonIsolatedCallerNode: Node?
        if functionType.children.at(startIndex)?.kind == .nonIsolatedCallerFunctionType {
            nonIsolatedCallerNode = functionType.children.at(startIndex)
            startIndex += 1
        }
        if functionType.children.at(startIndex)?.kind == .globalActorFunctionType {
            _ = await printOptional(functionType.children.at(startIndex))
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
            _ = await printName(nonIsolatedCallerNode)
        }

        if isSendable {
            target.write("@Sendable", context: .context(state: .printKeyword))
            target.writeSpace()
        }

        guard let parameterType = functionType.children.at(argIndex) else { return }

        await printFunctionParameters(labelList: labelList, parameterType: parameterType, showTypes: true)

        if isAsync {
            target.writeSpace()
            target.write("async", context: .context(state: .printKeyword))
        }
        if let thrownErrorNode {
            _ = await printName(thrownErrorNode)
        }

        let returnType = functionType.children.at(argIndex + 1)

        if !isBlockOrClosure, let typeNode = returnType?.children.first, typeNode.kind == .type, let tuple = typeNode.children.first, tuple.kind == .tuple, tuple.children.isEmpty {
            return
        } else if isAllocator {
            return
        }

        target.write(" -> ")

        if hasSendingResult {
            target.write("sending", context: .context(state: .printKeyword))
            target.writeSpace()
        }

        await printOptional(returnType)
    }

    private mutating func printFunctionParameters(labelList: Node?, parameterType: Node, showTypes: Bool) async {
        guard parameterType.kind == .argumentTuple else { return }
        guard let t = parameterType.children.first, t.kind == .type else { return }
        guard let parameters = t.children.first else { return }

        if parameters.kind != .tuple {
            if showTypes {
                target.write("(_: ")
                _ = await printName(parameters)
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
                _ = await printName(tuple.element)
                if tuple.offset != parameters.children.count - 1 {
                    target.write(", ")
                }
            }
        }
        target.write(")")
    }

    private mutating func printTupleElement(_ name: Node) async {
        if let label = name.children.first(where: { $0.kind == .tupleElementName }) {
            target.write("\(label.text ?? ""): ")
        }
        guard let type = name.children.first(where: { $0.kind == .type }) else { return }
        _ = await printName(type)
        if let _ = name.children.first(where: { $0.kind == .variadicMarker }) {
            target.write("...")
        }
    }

    private mutating func printConventionWithMangledCType(_ name: Node, label: String) async {
        target.write("@convention(\(label)", context: .context(state: .printKeyword))
        if let firstChild = name.children.first, firstChild.kind == .clangType {
            target.write(", mangledCType: \"")
            _ = await printName(firstChild)
            target.write("\"")
        }
        target.write(") ")
    }

    private mutating func printReturnType(_ name: Node) async {
        if name.children.isEmpty, let t = name.text {
            target.write(t)
        } else {
            await printChildren(name)
        }
    }

    mutating func printTypeThrowsAnnotation(_ name: Node) async {
        target.writeSpace()
        target.write("throws", context: .context(state: .printKeyword))
        target.write("(")
        if let child = name.children.first {
            _ = await printName(child)
        }
        target.write(")")
    }

    mutating func printGlobalActorFunctionType(_ name: Node) async {
        if let firstChild = name.children.first {
            target.write("@")
            _ = await printName(firstChild)
            target.write(" ")
        }
    }

    mutating func printDifferentiableFunctionType(_ name: Node) async {
        target.write("@differentiable")
        switch UnicodeScalar(UInt8(name.index ?? 0)) {
        case "f": target.write("(_forward)")
        case "r": target.write("(reverse)")
        case "l": target.write("(_linear)")
        default: break
        }
    }

    mutating func printLabelList(name: Node, type: Node, genericFunctionTypeList: Node?) async {
        var labelList = name.children.first(of: .labelList)

        if let argumentTuple = name.first(of: .argumentTuple), let tuple = argumentTuple.first(of: .tuple) {
            if !tuple.children.isEmpty, labelList == nil || labelList!.children.isEmpty {
                labelList = Node.create(kind: .labelList, children: (0 ..< tuple.children.count).map { _ in NodeFactory.firstElementMarker })
            }
        }

        if labelList != nil || genericFunctionTypeList != nil {
            if let genericFunctionTypeList {
                await printChildren(genericFunctionTypeList, prefix: "<", suffix: ">", separator: ", ")
            }
            var functionType = type
            if type.kind == .dependentGenericType {
                if genericFunctionTypeList == nil {
                    await printOptional(type.children.first)
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
            await printFunctionType(functionType, labelList: labelList, isAllocator: name.kind == .allocator, isBlockOrClosure: false)
        } else {
            var context = Context()
            context.isAllocator = name.kind == .allocator
            context.isBlockOrClosure = false
            await printName(type, context: context)
        }
    }
}
