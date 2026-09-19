import SwiftDeclaration
import Demangling

/// The slice of printer state the function-type layer reads and writes.
protocol FunctionTypeNodePrintableContext: NodePrintableContext {
    var packExpansionDepth: Int { get set }
    var knownPackParameterNames: Set<String> { get set }
}

protocol FunctionTypeNodePrintable: NodePrintable where Context: FunctionTypeNodePrintableContext {
    mutating func printNameInFunction(_ name: Node, options: NodePrintOptions) async -> Bool
    mutating func printFunctionType(_ functionType: Node, labelList: Node?, isAllocator: Bool, isBlockOrClosure: Bool) async
}

extension FunctionTypeNodePrintable {
    mutating func printNameInFunction(_ name: Node, options: NodePrintOptions) async -> Bool {
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
            await printFunctionType(name, labelList: nil, isAllocator: options.isAllocator, isBlockOrClosure: options.isBlockOrClosure)
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
            await printPackExpansion(name)
        default:
            return false
        }
        return true
    }

    /// A pack expansion — `repeat each A` in source.
    ///
    /// The `each` is not in the mangling. A parameter's pack-ness is recorded
    /// once on the generic SIGNATURE (`dependentGenericParamPackMarker`) and
    /// never at the use site, so this node's pattern demangles to a plain
    /// parameter reference and renders as `repeat A`, which does not compile.
    /// `printGenericSignature` recovers `each` at the DECLARATION (`<each A>`)
    /// only because the signature is right there in the node it is printing;
    /// at a use site the signature is not in the tree at all, and the upstream
    /// `NodePrinter` (whose product is a debug demangle, not source) does not
    /// try.
    ///
    /// The node names the pack itself, so nothing has to be inferred: a
    /// `packExpansion` has TWO children — child 0 is the pattern, child 1 is
    /// the **count type**, the pack whose length drives the expansion. For
    /// `repeat (T, each U)` the count type is `U`, which is exactly the
    /// parameter that takes `each`, and `T` is left alone. (The mangling spells
    /// this out: `x_q_t` `q_` `Qp` — pattern, count type, expansion operator.)
    ///
    /// The parameter prints parenthesized (`(each A)`) unconditionally,
    /// because `each` binds tighter than a suffix: `repeat each A.Type` and
    /// `repeat each A?` are both rejected outright ("'each' cannot be applied
    /// to non-pack type"), while the parenthesized spelling type-checks in
    /// every position measured — bare argument, metatype, optional, and
    /// nested generic argument.
    ///
    /// The count type names only ONE pack, which is all a type's field ever
    /// needs — a generic type may declare at most one ("generic type cannot
    /// declare more than one type pack"). Several packs under one expansion is
    /// reachable only on a function (`g<each A, each B>(_: (repeat (each A,
    /// each B)))`), and there the signature is in the same tree and the same
    /// printer, so ``printGenericSignature`` has already recorded every pack
    /// into ``knownPackParameterNames`` by the time the parameter type prints.
    /// The two sources cover each other's gap.
    mutating func printPackExpansion(_ name: Node) async {
        context.packExpansionDepth += 1
        defer { context.packExpansionDepth -= 1 }
        if let countTypeName = Self.countTypeParameterName(in: name) {
            context.knownPackParameterNames.insert(countTypeName)
        }
        await printFirstChild(name, prefix: "repeat ", prefixContext: .context(state: .printKeyword))
    }

    /// The generic parameter named by the expansion's count type (child 1), or
    /// nil when it is absent or is not a single parameter.
    static func countTypeParameterName(in expansion: Node) -> String? {
        guard let countType = expansion.children.at(1) else { return nil }
        var names: Set<String> = []
        // `Node` iterates preorder including itself, so this covers a count
        // type that arrives wrapped in a `type` node.
        for node in countType where node.kind == .dependentGenericParamType {
            guard let text = node.text else { continue }
            names.insert(text)
            if names.count > 1 { return nil }
        }
        return names.first
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

        let argumentTupleIndex = functionType.children.count - 2
        var startIndex = 0
        var isSendable = false
        var isAsync = false
        var hasSendingResult = false
        var differentiabilityKind = UnicodeScalar(0)
        if functionType.children.at(startIndex)?.kind == .clangType {
            startIndex += 1
        }
        if functionType.children.at(startIndex)?.kind == .sendingResultFunctionType {
            startIndex += 1
            hasSendingResult = true
        }
        if functionType.children.at(startIndex)?.kind == .isolatedAnyFunctionType {
            await printOptional(functionType.children.at(startIndex))
            startIndex += 1
        }
        var nonIsolatedCallerNode: Node?
        if functionType.children.at(startIndex)?.kind == .nonIsolatedCallerFunctionType {
            nonIsolatedCallerNode = functionType.children.at(startIndex)
            startIndex += 1
        }
        if functionType.children.at(startIndex)?.kind == .globalActorFunctionType {
            await printOptional(functionType.children.at(startIndex))
            startIndex += 1
        }
        if functionType.children.at(startIndex)?.kind == .differentiableFunctionType {
            differentiabilityKind = UnicodeScalar(UInt8(functionType.children.at(startIndex)?.index ?? 0))
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

        switch differentiabilityKind {
        case "f": target.write("@differentiable(_forward) ")
        case "r": target.write("@differentiable(reverse) ")
        case "l": target.write("@differentiable(_linear) ")
        case "d": target.write("@differentiable ")
        default: break
        }

        if let nonIsolatedCallerNode {
            await printName(nonIsolatedCallerNode)
        }

        if isSendable {
            target.write("@Sendable", context: .context(state: .printKeyword))
            target.writeSpace()
        }

        guard let parameterType = functionType.children.at(argumentTupleIndex) else { return }

        await printFunctionParameters(labelList: labelList, parameterType: parameterType, showTypes: true)

        if isAsync {
            target.writeSpace()
            target.write("async", context: .context(state: .printKeyword))
        }
        if let thrownErrorNode {
            await printName(thrownErrorNode)
        }

        let returnType = functionType.children.at(argumentTupleIndex + 1)

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
        guard let typeNode = parameterType.children.first, typeNode.kind == .type else { return }
        guard let parameters = typeNode.children.first else { return }

        if parameters.kind != .tuple {
            if showTypes {
                target.write("(_: ")
                await printParameterType(parameters)
                target.write(")")
            } else {
                target.write("(_:)")
            }
            return
        }

        target.write("(")
        for (offset, element) in parameters.children.enumerated() {
            if let label = labelList?.children.at(offset) {
                target.write(label.kind == .identifier ? (label.text ?? "") : "_", context: .context(for: parameterType, state: .printFunctionParameters))
                target.write(":")
                if showTypes {
                    target.write(" ")
                }
            } else if !showTypes {
                if let label = element.children.first(where: { $0.kind == .tupleElementName }) {
                    target.write(label.text ?? "", context: .context(for: parameterType, state: .printFunctionParameters))
                    target.write(":")
                } else {
                    target.write("_", context: .context(for: parameterType, state: .printFunctionParameters))
                    target.write(":")
                }
            }

            if showTypes {
                await printParameterTupleElement(element)
                if offset != parameters.children.count - 1 {
                    target.write(", ")
                }
            }
        }
        target.write(")")
    }

    /// Print a tuple element that lives in a parameter position. Mirrors
    /// `printTupleElement`, but prefixes `@escaping` when the wrapped
    /// type is a closure that is escaping by default.
    private mutating func printParameterTupleElement(_ name: Node) async {
        if let label = name.children.first(where: { $0.kind == .tupleElementName }) {
            target.write("\(label.text ?? ""): ")
        }
        guard let typeNode = name.children.first(where: { $0.kind == .type }) else { return }
        await printParameterType(typeNode)
        if name.children.first(where: { $0.kind == .variadicMarker }) != nil {
            target.write("...")
        }
    }

    /// Print a parameter type node, prepending `@escaping` for top-level
    /// closure-style function types as Swift source requires.
    private mutating func printParameterType(_ typeNode: Node) async {
        if needsEscapingAttribute(forParameterTypeNode: typeNode) {
            target.write("@escaping", context: .context(state: .printKeyword))
            target.writeSpace()
        }
        await printName(typeNode)
    }

    /// Decide whether a parameter type requires the `@escaping` attribute.
    ///
    /// In Swift source, `@escaping` is only allowed on the *outermost* function
    /// type of a parameter declaration; nested closure types inside a return
    /// position or inside another closure's signature are escaping by default
    /// but cannot be annotated. This matches that rule.
    ///
    /// The check excludes node kinds that already carry their own attribute or
    /// are non-escaping by definition (`noEscapeFunctionType`, `autoClosureType`,
    /// `cFunctionPointer`, `objCBlock`, `thinFunctionType`, etc.).
    private func needsEscapingAttribute(forParameterTypeNode typeNode: Node) -> Bool {
        var current: Node? = typeNode
        while let node = current {
            switch node.kind {
            case .type:
                current = node.children.first
            case .functionType, .escapingAutoClosureType:
                return true
            default:
                return false
            }
        }
        return false
    }

    private mutating func printTupleElement(_ name: Node) async {
        if let label = name.children.first(where: { $0.kind == .tupleElementName }) {
            target.write("\(label.text ?? ""): ")
        }
        guard let type = name.children.first(where: { $0.kind == .type }) else { return }
        await printName(type)
        if let _ = name.children.first(where: { $0.kind == .variadicMarker }) {
            target.write("...")
        }
    }

    private mutating func printConventionWithMangledCType(_ name: Node, label: String) async {
        target.write("@convention(\(label)", context: .context(state: .printKeyword))
        if let firstChild = name.children.first, firstChild.kind == .clangType {
            target.write(", mangledCType: \"")
            await printName(firstChild)
            target.write("\"")
        }
        target.write(") ")
    }

    private mutating func printReturnType(_ name: Node) async {
        if name.children.isEmpty, let text = name.text {
            target.write(text)
        } else {
            await printChildren(name)
        }
    }

    mutating func printTypeThrowsAnnotation(_ name: Node) async {
        target.writeSpace()
        target.write("throws", context: .context(state: .printKeyword))
        target.write("(")
        if let child = name.children.first {
            await printName(child)
        }
        target.write(")")
    }

    mutating func printGlobalActorFunctionType(_ name: Node) async {
        if let firstChild = name.children.first {
            target.write("@")
            await printName(firstChild)
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

}

extension FunctionTypeNodePrintable where Self: DependentGenericNodePrintable {
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
                    if let signature = type.children.first, signature.kind == .dependentGenericSignature {
                        await printGenericSignature(signature, enclosingGenericType: type)
                    } else {
                        await printOptional(type.children.first)
                    }
                }
                if let dependentType = type.children.at(1) {
                    if dependentType.needSpaceBeforeType {
                        target.write(" ")
                    }
                    if let first = dependentType.children.first {
                        functionType = first
                    }
                }
            }
            await printFunctionType(functionType, labelList: labelList, isAllocator: name.kind == .allocator, isBlockOrClosure: false)
        } else {
            await printName(type, options: NodePrintOptions(isAllocator: name.kind == .allocator, isBlockOrClosure: false))
        }
    }
}
