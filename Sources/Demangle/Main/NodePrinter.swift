import Semantic

struct NodePrinter: Sendable {
    var target: SemanticString
    var specializationPrefixPrinted: Bool
    var options: DemangleOptions
    var hidingCurrentModule: String = ""
    
    init(options: DemangleOptions = .default) {
        self.target = .init()
        self.specializationPrefixPrinted = false
        self.options = options
    }

    func shouldPrintContext(_ context: Node) -> Bool {
        guard options.contains(.qualifyEntities) else {
            return false
        }
        if !options.contains(.showModuleInDependentMemberType), let dependentMemberType = context.parent?.parent?.parent?.parent, dependentMemberType.kind == .dependentMemberType  {
            return false
        }
        if context.kind == .module, let text = context.text, !text.isEmpty {
            switch text {
            case stdlibName: return options.contains(.displayStdlibModule)
            case objcModule: return options.contains(.displayObjCModule)
            case hidingCurrentModule: return false
            default:
                if text.starts(with: lldbExpressionsModuleNamePrefix) {
                    return options.contains(.displayDebuggerGeneratedModule)
                }
            }
        }
        return true
    }

    mutating func printOptional(_ optional: Node?, prefix: String? = nil, suffix: String? = nil, asPrefixContext: Bool = false) -> Node? {
        guard let o = optional else { return nil }
        if options.contains(.showPrefixAndSuffix) {
            prefix.map { target.write($0) }
        }
        let r = printName(o)
        if options.contains(.showPrefixAndSuffix) {
            suffix.map { target.write($0) }
        }
        return r
    }

    mutating func printFirstChild(_ ofName: Node, prefix: String? = nil, suffix: String? = nil, asPrefixContext: Bool = false) {
        _ = printOptional(ofName.children.at(0), prefix: prefix, suffix: suffix)
    }

    mutating func printSequence<S>(_ names: S, prefix: String? = nil, suffix: String? = nil, separator: String? = nil) where S: Sequence, S.Element == Node {
        var isFirst = true
        prefix.map { target.write($0) }
        for c in names {
            if let s = separator, !isFirst {
                target.write(s)
            } else {
                isFirst = false
            }
            _ = printName(c)
        }
        suffix.map { target.write($0) }
    }

    mutating func printChildren(_ ofName: Node, prefix: String? = nil, suffix: String? = nil, separator: String? = nil) {
        printSequence(ofName.children, prefix: prefix, suffix: suffix, separator: separator)
    }

    mutating func printMacro(name: Node, asPrefixContext: Bool, label: String) -> Node? {
        return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .noType, hasName: true, extraName: "\(label) macro @\(name.children.at(2)?.description ?? "") expansion #", extraIndex: (name.children.at(3)?.index ?? 0) + 1)
    }

    mutating func printAnonymousContext(_ name: Node) {
        if options.contains(.qualifyEntities), options.contains(.displayExtensionContexts) {
            _ = printOptional(name.children.at(1))
            target.write(".(unknown context at " + (name.children.first?.text ?? "") + ")")
            if let second = name.children.at(2), !second.children.isEmpty {
                target.write("<")
                _ = printName(second)
                target.write(">")
            }
        }
    }

    mutating func printExtension(_ name: Node) {
        if options.contains(.qualifyEntities), options.contains(.displayExtensionContexts) {
            printFirstChild(name, prefix: "(extension in ", suffix: "):", asPrefixContext: true)
        }
        _ = printOptional(name.children.at(1))
        _ = printOptional(!options.contains(.printForTypeName) ? name.children.at(2) : nil)
    }

    mutating func printSuffix(_ name: Node) {
        if options.contains(.displayUnmangledSuffix) {
            target.write(" with unmangled suffix ")
            quotedString(name.text ?? "")
        }
    }

    mutating func printPrivateDeclName(_ name: Node) {
        _ = printOptional(name.children.at(1), prefix: options.contains(.showPrivateDiscriminators) ? "(" : nil)
        target.write(options.contains(.showPrivateDiscriminators) ? "\(name.children.count > 1 ? " " : "(")in \(name.children.at(0)?.text ?? ""))" : "")
    }

    mutating func printModule(_ name: Node) {
        if options.contains(.displayModuleNames) {
            target.write(name.text ?? "")
        }
    }

    mutating func printReturnType(_ name: Node) {
        if name.children.isEmpty, let t = name.text {
            target.write(t)
        } else {
            printChildren(name)
        }
    }

    mutating func printRetroactiveConformance(_ name: Node) {
        if name.children.count == 2 {
            printChildren(name, prefix: "retroactive @ ")
        }
    }

    mutating func printGenericSpecializationParam(_ name: Node) {
        printFirstChild(name)
        _ = printOptional(name.children.at(1), prefix: " with ")
        name.children.slice(2, name.children.endIndex).forEach {
            target.write(" and ")
            _ = printName($0)
        }
    }

    mutating func printFunctionSignatureSpecializationParam(_ name: Node) {
        var idx = 0
        while idx < name.children.count {
            guard let firstChild = name.children.at(idx), let v = firstChild.index else { return }
            let k = FunctionSigSpecializationParamKind(rawValue: v)
            switch k {
            case .boxToValue,
                 .boxToStack,
                 .inOutToOut:
                _ = printOptional(name.children.at(idx))
                idx += 1
            case .constantPropFunction,
                 .constantPropGlobal:
                _ = printOptional(name.children.at(idx), prefix: "[", suffix: " : ")
                guard let t = name.children.at(idx + 1)?.text else { return }
                let demangedName = (try? demangleAsNode(t))?.description ?? ""
                if demangedName.isEmpty {
                    target.write(t)
                } else {
                    target.write(demangedName)
                }
                target.write("]")
                idx += 2
            case .constantPropInteger: fallthrough
            case .constantPropFloat:
                _ = printOptional(name.children.at(idx), prefix: "[")
                _ = printOptional(name.children.at(idx + 1), prefix: " : ", suffix: "]")
                idx += 2
            case .constantPropString:
                _ = printOptional(name.children.at(idx), prefix: "[")
                _ = printOptional(name.children.at(idx + 1), prefix: " : ")
                _ = printOptional(name.children.at(idx + 2), prefix: "'", suffix: "']")
                idx += 3
            case .constantPropKeyPath:
                _ = printOptional(name.children.at(idx), prefix: "[")
                _ = printOptional(name.children.at(idx + 1), prefix: " : ")
                _ = printOptional(name.children.at(idx + 2), prefix: "<")
                _ = printOptional(name.children.at(idx + 3), prefix: ",", suffix: ">]")
                idx += 4
            case .closureProp:
                _ = printOptional(name.children.at(idx), prefix: "[")
                _ = printOptional(name.children.at(idx + 1), prefix: " : ", suffix: ", Argument Types : [")
                idx += 2
                while idx < name.children.count, let c = name.children.at(idx), c.kind == .type {
                    _ = printName(c)
                    idx += 1
                    if idx < name.children.count, name.children.at(idx)?.text != nil {
                        target.write(", ")
                    }
                }
                target.write("]")
            default:
                _ = printOptional(name.children.at(idx))
                idx += 1
            }
        }
    }

    mutating func printFunctionSignatureSpecializationParamKind(_ name: Node) {
        let raw = name.index ?? 0
        var printedOptionSet = false
        if raw & FunctionSigSpecializationParamKind.existentialToGeneric.rawValue != 0 {
            printedOptionSet = true
            target.write(FunctionSigSpecializationParamKind.existentialToGeneric.description)
        }
        if raw & FunctionSigSpecializationParamKind.dead.rawValue != 0 {
            if printedOptionSet { target.write(" and ") }
            printedOptionSet = true
            target.write(FunctionSigSpecializationParamKind.dead.description)
        }
        if raw & FunctionSigSpecializationParamKind.ownedToGuaranteed.rawValue != 0 {
            if printedOptionSet { target.write(" and ") }
            printedOptionSet = true
            target.write(FunctionSigSpecializationParamKind.ownedToGuaranteed.description)
        }
        if raw & FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue != 0 {
            if printedOptionSet { target.write(" and ") }
            printedOptionSet = true
            target.write(FunctionSigSpecializationParamKind.guaranteedToOwned.description)
        }
        if raw & FunctionSigSpecializationParamKind.sroa.rawValue != 0 {
            if printedOptionSet { target.write(" and ") }
            printedOptionSet = true
            target.write(FunctionSigSpecializationParamKind.sroa.description)
        }

        if printedOptionSet {
            return
        }

        if let single = FunctionSigSpecializationParamKind(rawValue: raw) {
            target.write(single.description)
        }
    }

    mutating func printLazyProtocolWitnesstableAccessor(_ name: Node) {
        _ = printOptional(name.children.at(0), prefix: "lazy protocol witness table accessor for type ")
        _ = printOptional(name.children.at(1), prefix: " and conformance ")
    }

    mutating func printLazyProtocolWitnesstableCacheVariable(_ name: Node) {
        _ = printOptional(name.children.at(0), prefix: "lazy protocol witness table cache variable for type ")
        _ = printOptional(name.children.at(1), prefix: " and conformance ")
    }

    mutating func printVTableThunk(_ name: Node) {
        _ = printOptional(name.children.at(1), prefix: "vtable thunk for ")
        _ = printOptional(name.children.at(0), prefix: " dispatching to ")
    }

    mutating func printProtocolWitness(_ name: Node) {
        _ = printOptional(name.children.at(1), prefix: "protocol witness for ")
        _ = printOptional(name.children.at(0), prefix: " in conformance ")
    }

    mutating func printPartialApplyForwarder(_ name: Node) {
        target.write("partial apply\(options.contains(.shortenPartialApply) ? "" : " forwarder")")
        if !name.children.isEmpty {
            printChildren(name, prefix: " for ")
        }
    }

    mutating func printPartialApplyObjCForwarder(_ name: Node) {
        target.write("partial apply\(options.contains(.shortenPartialApply) ? "" : " ObjC forwarder")")
        if !name.children.isEmpty {
            printChildren(name, prefix: " for ")
        }
    }

    mutating func printKeyPathAccessorThunkHelper(_ name: Node) {
        printFirstChild(name, prefix: "key path \(name.kind == .keyPathGetterThunkHelper ? "getter" : "setter") for ", suffix: " : ")
        for child in name.children.dropFirst() {
            if child.kind == .isSerialized {
                target.write(", ")
            }
            _ = printName(child)
        }
    }

    mutating func printKeyPathEqualityThunkHelper(_ name: Node) {
        target.write("key path index \(name.kind == .keyPathEqualsThunkHelper ? "equality" : "hash") operator for ")
        var dropLast = false
        if let lastChild = name.children.last, lastChild.kind == .dependentGenericSignature {
            _ = printName(lastChild)
            dropLast = true
        }
        printSequence(dropLast ? Array(name.children.dropLast()) : name.children, prefix: "(", suffix: ")", separator: ", ")
    }

    mutating func printFieldOffset(_ name: Node) {
        printFirstChild(name)
        _ = printOptional(name.children.at(1), prefix: "field offset for ", asPrefixContext: true)
    }

    mutating func printReabstractionThunk(_ name: Node) {
        if options.contains(.shortenThunk) {
            _ = printOptional(name.children.at(name.children.count - 2), prefix: "thunk for ")
        } else {
            target.write("reabstraction thunk ")
            target.write(name.kind == .reabstractionThunkHelper ? "helper " : "")
            _ = printOptional(name.children.at(name.children.count - 3), suffix: " ")
            _ = printOptional(name.children.at(name.children.count - 1), prefix: "from ")
            _ = printOptional(name.children.at(name.children.count - 2), prefix: " to ")
        }
    }

    mutating func printAssociatedConformanceDescriptor(_ name: Node) {
        _ = printOptional(name.children.at(0), prefix: "associated conformance descriptor for ")
        _ = printOptional(name.children.at(1), prefix: ".")
        _ = printOptional(name.children.at(2), prefix: ": ")
    }

    mutating func printDefaultAssociatedConformanceAccessor(_ name: Node) {
        _ = printOptional(name.children.at(0), prefix: "default associated conformance accessor for ")
        _ = printOptional(name.children.at(1), prefix: ".")
        _ = printOptional(name.children.at(2), prefix: ": ")
    }

    mutating func printAssociatedTypeMetadataAccessor(_ name: Node) {
        _ = printOptional(name.children.at(1), prefix: "associated type metadata accessor for ")
        _ = printOptional(name.children.at(0), prefix: " in ")
    }

    mutating func printAssociatedTypeWitnessTableAccessor(_ name: Node) {
        _ = printOptional(name.children.at(1), prefix: "associated type witness table accessor for ")
        _ = printOptional(name.children.at(2), prefix: " : ")
        _ = printOptional(name.children.at(0), prefix: " in ")
    }

    mutating func printValueWitness(_ name: Node) {
        target.write(ValueWitnessKind(rawValue: name.index ?? 0)?.description ?? "")
        target.write(options.contains(.shortenValueWitness) ? " for " : " value witness for ")
        printFirstChild(name)
    }

    mutating func printConcreteProtocolConformance(_ name: Node) {
        target.write("concrete protocol conformance ")
        if let index = name.index {
            target.write(" #\(index)")
        }
        printFirstChild(name)
        target.write(" to ")
        _ = printOptional(name.children.at(1))
        if let thirdChild = name.children.at(2), !thirdChild.children.isEmpty {
            target.write(" with conditional requirements: ")
            _ = printName(thirdChild)
        }
    }

    mutating func printMetatype(_ name: Node) {
        if name.children.count == 2 {
            printFirstChild(name, suffix: " ")
        }
        guard let type = name.children.at(name.children.count == 2 ? 1 : 0)?.children.first else { return }
        let needParens = !type.isSimpleType
        target.write(needParens ? "(" : "")
        _ = printName(type)
        target.write(needParens ? ")" : "")
        target.write(type.kind.isExistentialType ? ".Protocol" : ".Type")
    }

    mutating func printExistentialMetatype(_ name: Node) {
        if name.children.count == 2 {
            printFirstChild(name, suffix: " ")
        }
        _ = printOptional(name.children.at(name.children.count == 2 ? 1 : 0), suffix: ".Type")
    }

    mutating func printAssociatedTypeRef(_ name: Node) {
        printFirstChild(name)
        target.write(".\(name.children.at(1)?.text ?? "")")
    }

    mutating func printProtocolList(_ name: Node) {
        guard let typeList = name.children.first else { return }
        if typeList.children.isEmpty {
            target.write("Any")
        } else {
            printChildren(typeList, separator: " & ")
        }
    }

    mutating func printProtocolListWithClass(_ name: Node) {
        guard name.children.count >= 2 else { return }
        _ = printOptional(name.children.at(1), suffix: " & ")
        if let protocolsTypeList = name.children.first?.children.first {
            printChildren(protocolsTypeList, separator: " & ")
        }
    }

    mutating func printProtocolListWithAnyObject(_ name: Node) {
        guard let prot = name.children.first, let protocolsTypeList = prot.children.first else { return }
        if protocolsTypeList.children.count > 0 {
            printChildren(protocolsTypeList, suffix: " & ", separator: " & ")
        }
        if options.contains(.qualifyEntities) {
            target.write("Swift.")
        }
        target.write("AnyObject")
    }

    mutating func printProtocolConformance(_ name: Node) {
        if name.children.count == 4 {
            _ = printOptional(name.children.at(2), prefix: "property behavior storage of ")
            _ = printOptional(name.children.at(0), prefix: " in ")
            _ = printOptional(name.children.at(1), prefix: " : ")
        } else {
            printFirstChild(name)
            if options.contains(.displayProtocolConformances) {
                _ = printOptional(name.children.at(1), prefix: " : ")
                _ = printOptional(name.children.at(2), prefix: " in ")
            }
        }
    }

    mutating func printImplParameter(_ name: Node) {
        printFirstChild(name, suffix: " ")
        if name.children.count == 3 {
            _ = printOptional(name.children.at(1))
        } else if name.children.count == 4 {
            _ = printOptional(name.children.at(1))
            _ = printOptional(name.children.at(2))
        }
        _ = printOptional(name.children.last)
    }

    mutating func printDependentProtocolConformanceAssociated(_ name: Node) {
        target.write("dependent associated protocol conformance ")
        if let index = name.children.at(2)?.index {
            target.write("#\(index) ")
        }
        printFirstChild(name)
        target.write(" to ")
        _ = printOptional(name.children.at(1))
    }

    mutating func printDependentProtocolConformanceInherited(_ name: Node) {
        target.write("dependent inherited protocol conformance ")
        if let index = name.children.at(2)?.index {
            target.write("#\(index) ")
        }
        printFirstChild(name)
        target.write(" to ")
        _ = printOptional(name.children.at(1))
    }

    mutating func printDependentProtocolConformanceRoot(_ name: Node) {
        target.write("dependent root protocol conformance ")
        if let index = name.children.at(2)?.index {
            target.write("#\(index) ")
        }
        printFirstChild(name)
        target.write(" to ")
        _ = printOptional(name.children.at(1))
    }

    static func genericParameterName(depth: UInt64, index: UInt64) -> String {
        var name = ""
        var index = index
        repeat {
            if let scalar = UnicodeScalar(UnicodeScalar("A").value + UInt32(index % 26)) {
                name.unicodeScalars.append(scalar)
            }
            index /= 26
        } while index != 0
        if depth != 0 {
            name.append("\(depth)")
        }
        return name
    }

    mutating func printGenericSignature(_ name: Node) {
        target.write("<")
        var numGenericParams = 0
        for c in name.children {
            guard c.kind == .dependentGenericParamCount else { break }
            numGenericParams += 1
        }
        var firstRequirement = numGenericParams
        for var c in name.children.dropFirst(numGenericParams) {
            if c.kind == .type {
                c = c.children.first ?? c
            }
            guard c.kind == .dependentGenericParamPackMarker || c.kind == .dependentGenericParamValueMarker else {
                break
            }
            firstRequirement += 1
        }

        let isGenericParamPack = { (depth: UInt64, index: UInt64) -> Bool in
            for var child in name.children.dropFirst(numGenericParams).prefix(firstRequirement) {
                guard child.kind == .dependentGenericParamPackMarker else { continue }

                child = child.children.first ?? child
                guard child.kind == .type else { continue }

                child = child.children.first ?? child
                guard child.kind == .dependentGenericParamType else { continue }

                if index == child.children.at(0)?.index, depth == child.children.at(1)?.index {
                    return true
                }
            }

            return false
        }

        let isGenericParamValue = { (depth: UInt64, index: UInt64) -> Node? in
            for var child in name.children.dropFirst(numGenericParams).prefix(firstRequirement) {
                guard child.kind == .dependentGenericParamValueMarker else { continue }
                child = child.children.first ?? child

                guard child.kind == .type else { continue }

                guard
                    let param = child.children.at(0),
                    let type = child.children.at(1),
                    param.kind == .dependentGenericParamType
                else {
                    continue
                }

                if index == param.children.at(0)?.index, depth == param.children.at(1)?.index {
                    return type
                }
            }

            return nil
        }

        for gpDepth in 0 ..< numGenericParams {
            if gpDepth != 0 {
                target.write("><")
            }

            guard let count = name.children.at(gpDepth)?.index else { continue }
            for index in 0 ..< count {
                if index != 0 {
                    target.write(", ")
                }

                // Limit the number of printed generic parameters. In practice this
                // it will never be exceeded. The limit is only important for malformed
                // symbols where count can be really huge.
                if index >= 128 {
                    target.write("...")
                    break
                }

                if isGenericParamPack(UInt64(gpDepth), UInt64(index)) {
                    target.write("each ")
                }

                let value = isGenericParamValue(UInt64(gpDepth), UInt64(index))
                if value != nil {
                    target.write("let ")
                }

                target.write(Self.genericParameterName(depth: UInt64(gpDepth), index: UInt64(index)))

                if let value {
                    target.write(": ")
                    _ = printName(value)
                }
            }
        }

        if firstRequirement != name.children.count {
            if options.contains(.displayWhereClauses) {
                target.write(" where ")
                printSequence(name.children.dropFirst(firstRequirement), separator: ", ")
            }
        }
        target.write(">")
    }

    mutating func printDependentGenericConformanceRequirement(_ name: Node) {
        printFirstChild(name)
        _ = printOptional(name.children.at(1), prefix: ": ")
    }

    mutating func printDependentGenericLayoutRequirement(_ name: Node) {
        guard let layout = name.children.at(1), let c = layout.text?.unicodeScalars.first else { return }
        printFirstChild(name, suffix: ": ")
        switch c {
        case "U": target.write("_UnknownLayout")
        case "R": target.write("_RefCountedObject")
        case "N": target.write("_NativeRefCountedObject")
        case "C": target.write("AnyObject")
        case "D": target.write("_NativeClass")
        case "T": target.write("_Trivial")
        case "E",
             "e": target.write("_Trivial")
        case "M",
             "m": target.write("_TrivialAtMost")
        default: break
        }
        if name.children.count > 2 {
            _ = printOptional(name.children.at(2), prefix: "(")
            _ = printOptional(name.children.at(3), prefix: ", ")
            target.write(")")
        }
    }

    mutating func printDependentGenericSameTypeRequirement(_ name: Node) {
        printFirstChild(name)
        _ = printOptional(name.children.at(1), prefix: " == ")
    }

    mutating func printDependentGenericType(_ name: Node) {
        guard let depType = name.children.at(1) else { return }
        printFirstChild(name)
        _ = printOptional(depType, prefix: depType.needSpaceBeforeType ? " " : "")
    }

    mutating func printDependentMemberType(_ name: Node) {
        printFirstChild(name)
        target.write(".")
        _ = printOptional(name.children.at(1))
    }

    mutating func printDependentAssociatedTypeRef(_ name: Node) {
        _ = printOptional(name.children.at(1), suffix: ".")
        printFirstChild(name)
    }

    mutating func printSilBoxTypeWithLayout(_ name: Node) {
        guard let layout = name.children.first else { return }
        _ = printOptional(name.children.at(1), suffix: " ")
        _ = printName(layout)
        if let genericArgs = name.children.at(2) {
            printSequence(genericArgs.children, prefix: " <", suffix: ">", separator: ", ")
        }
    }

    mutating func printSugaredOptional(_ name: Node) {
        if let type = name.children.first {
            let needParens = !type.isSimpleType
            target.write(needParens ? "(" : "")
            _ = printName(type)
            target.write(needParens ? ")" : "")
            target.write("?")
        }
    }

    mutating func printSugaredDictionary(_ name: Node) {
        printFirstChild(name, prefix: "[", suffix: " : ")
        _ = printOptional(name.children.at(1), suffix: "]")
    }

    mutating func printOpaqueType(_ name: Node) {
        printFirstChild(name)
        target.write(".")
        _ = printOptional(name.children.at(1))
    }

    mutating func printImplInvocationsSubstitutions(_ name: Node) {
        if let secondChild = name.children.at(0) {
            target.write(" for <")
            printChildren(secondChild, separator: ", ")
            target.write(">")
        }
    }

    mutating func printImplPatternSubstitutions(_ name: Node) {
        target.write("@substituted ")
        printFirstChild(name)
        if let secondChild = name.children.at(1) {
            target.write(" for <")
            printChildren(secondChild, separator: ", ")
            target.write(">")
        }
    }

    mutating func printImplDifferentiability(_ name: Node) {
        if let text = name.text, !text.isEmpty {
            target.write("\(text) ")
        }
    }

    mutating func printMacroExpansionLoc(_ name: Node) {
        if let module = name.children.at(0) {
            target.write("module ")
            _ = printName(module)
        }
        if let file = name.children.at(1) {
            target.write(" file ")
            _ = printName(file)
        }
        if let line = name.children.at(2) {
            target.write(" line ")
            _ = printName(line)
        }
        if let column = name.children.at(3) {
            target.write(" column ")
            _ = printName(column)
        }
    }

    mutating func printGlobalActorFunctionType(_ name: Node) {
        if let firstChild = name.children.first {
            target.write("@")
            _ = printName(firstChild)
            target.write(" ")
        }
    }

    mutating func printGlobalVariableOnceFunction(_ name: Node) {
        target.write(name.kind == .globalVariableOnceToken ? "one-time initialization token for " : "one-time initialization function for ")
        if let firstChild = name.children.first, shouldPrintContext(firstChild) {
            _ = printName(firstChild)
        }
    }

    mutating func printGlobalVariableOnceDeclList(_ name: Node) {
        if name.children.count == 1 {
            printFirstChild(name)
        } else {
            printSequence(name.children, prefix: "(", suffix: ")", separator: ", ")
        }
    }

    mutating func printTypeThrowsAnnotation(_ name: Node) {
        target.write(" throws(")
        if let child = name.children.first {
            _ = printName(child)
        }
        target.write(")")
    }

    mutating func printDifferentiableFunctionType(_ name: Node) {
        target.write("@differentiable")
        switch UnicodeScalar(UInt8(name.index ?? 0)) {
        case "f": target.write("(_forward)")
        case "r": target.write("(reverse)")
        case "l": target.write("(_linear)")
        default: break
        }
    }

    mutating func printDifferentiabilityWitness(_ name: Node) {
        let kindNodeIndex = name.children.count - (name.children.last?.kind == .dependentGenericSignature ? 4 : 3)
        let kind = (name.children.at(kindNodeIndex)?.index).flatMap { Differentiability($0) }
        switch kind {
        case .forward: target.write("forward-mode")
        case .reverse: target.write("reverse-mode")
        case .normal: target.write("normal")
        case .linear: target.write("linear")
        default: return
        }
        target.write(" differentiability witness for ")
        var idx = 0
        while idx < name.children.count, name.children.at(idx)?.kind != .index {
            _ = printOptional(name.children.at(idx))
            idx += 1
        }
        _ = printOptional(name.children.at(idx + 1), prefix: " with respect to parameters ")
        _ = printOptional(name.children.at(idx + 2), prefix: " and results ")
        _ = printOptional(name.children.at(idx + 3), prefix: " with ")
    }

    mutating func printAsyncAwaitResumePartialFunction(_ name: Node) {
        if options.contains(.showAsyncResumePartial) {
            target.write("(")
            _ = printName(name.children.first!)
            target.write(")")
            target.write(" await resume partial function for ")
        }
    }

    mutating func printAsyncSuspendResumePartialFunction(_ name: Node) {
        if options.contains(.showAsyncResumePartial) {
            target.write("(")
            _ = printName(name.children.first!)
            target.write(")")
            target.write(" suspend resume partial function for ")
        }
    }

    mutating func printExtendedExistentialTypeShape(_ name: Node) {
        let savedDisplayWhereClauses = options.contains(.displayWhereClauses)
        options.insert(.displayWhereClauses)
        var genSig: Node?
        let type: Node
        if name.children.count == 2 {
            genSig = name.children[0]
            type = name.children[1]
        } else {
            type = name.children[0]
        }
        target.write("existential shape for ")
        if let genSig {
            _ = printName(genSig)
            target.write(" ")
        }
        target.write("any ")
        _ = printName(type)
        if !savedDisplayWhereClauses {
            options.remove(.displayWhereClauses)
        }
    }

    mutating func printSymbolicExtendedExistentialType(_ name: Node) {
        guard let shape = name.children.first else { return }
        let isUnique = shape.kind == .uniqueExtendedExistentialTypeShapeSymbolicReference
        target.write("symbolic existential type (\(isUnique ? "" : "non-")unique) 0x")
        target.writeHex(shape.index ?? 0)
        target.write(" <")
        guard let second = name.children.at(1) else { return }
        _ = printName(second)
        if let third = name.children.at(2) {
            target.write(", ")
            _ = printName(third)
        }
        target.write(">")
    }

    mutating func printTupleElement(_ name: Node) {
        if let label = name.children.first(where: { $0.kind == .tupleElementName }) {
            target.write("\(label.text ?? ""): ")
        }
        guard let type = name.children.first(where: { $0.kind == .type }) else { return }
        _ = printName(type)
        if let _ = name.children.first(where: { $0.kind == .variadicMarker }) {
            target.write("...")
        }
    }

    mutating func printObjCAsyncCompletionHandlerImpl(_ name: Node) {
        if name.kind == .predefinedObjCAsyncCompletionHandlerImpl {
            target.write("predefined ")
        }
        target.write("@objc completion handler block implementation for ")
        if name.children.count >= 4 {
            _ = printOptional(name.children.at(3))
        }
        printFirstChild(name, suffix: " with result type ")
        _ = printOptional(name.children.at(1))
        switch name.children.at(2)?.index {
        case 0: break
        case 1: target.write(" nonzero on error ")
        case 2: target.write(" zero on error ")
        default: target.write(" <invalid error flag>")
        }
    }

    mutating func printImplInvocationSubstitutions(_ name: Node) {
        if let secondChild = name.children.at(0) {
            target.write(" for <")
            printChildren(secondChild, separator: ", ")
            target.write(">")
        }
    }

    mutating func printImplDifferentiabilityKind(_ name: Node) {
        target.write("@differentiable")
        if case let .index(value) = name.contents, let differentiability = Differentiability(value) {
            switch differentiability {
            case .normal: break
            case .linear: target.write("(_linear)")
            case .forward: target.write("(_forward)")
            case .reverse: target.write("(reverse)")
            }
        }
    }

    mutating func printImplCoroutineKind(_ name: Node) {
        guard case let .name(value) = name.contents, !value.isEmpty else { return }
        target.write("@\(value)")
    }

    mutating func printImplFunctionConvention(_ name: Node) {
        target.write("@convention(")
        if let second = name.children.at(1) {
            target.write("\(name.children.at(0)?.text ?? ""), mangledCType: \"")
            _ = printName(second)
            target.write("\"")
        } else {
            target.write("\(name.children.at(0)?.text ?? "")")
        }
        target.write(")")
    }

    mutating func printImplParameterName(_ name: Node) {
        guard case let .name(value) = name.contents, !value.isEmpty else { return }
        target.write("\(value) ")
    }

    mutating func printBaseConformanceDescriptor(_ name: Node) {
        printFirstChild(name, prefix: "base conformance descriptor for ")
        _ = printOptional(name.children.at(1), prefix: ": ")
    }

    mutating func printReabstractionThunkHelperWithSelf(_ name: Node) {
        target.write("reabstraction thunk ")
        var idx = 0
        if name.children.count == 4 {
            printFirstChild(name, suffix: " ")
            idx += 1
        }
        _ = printOptional(name.children.at(idx + 2), prefix: "from ")
        _ = printOptional(name.children.at(idx + 1), prefix: " to ")
        _ = printOptional(name.children.at(idx), prefix: " self ")
    }

    mutating func printReabstracctionThunkHelperWithGlobalActor(_ name: Node) {
        printFirstChild(name)
        _ = printOptional(name.children.at(1), prefix: " with global actor constraint")
    }

    mutating func printBuildInFixedArray(_ name: Node) {
        _ = printOptional(name.children.first, prefix: "Builtin.FixedArray<")
        _ = printOptional(name.children.at(1), prefix: ", ", suffix: ">")
    }

    mutating func printAutoDiffFunctionOrSimpleThunk(_ name: Node) {
        var prefixEndIndex = 0
        while prefixEndIndex < name.children.count, name.children[prefixEndIndex].kind != .autoDiffFunctionKind {
            prefixEndIndex += 1
        }

        let funcKind = name.children.at(prefixEndIndex)
        let paramIndices = name.children.at(prefixEndIndex + 1)
        let resultIndices = name.children.at(prefixEndIndex + 2)
        if name.kind == .autoDiffDerivativeVTableThunk {
            target.write("vtable thunk for ")
        }
        _ = printOptional(funcKind)
        target.write(" of ")
        var optionalGenSig: Node?
        for i in 0 ..< prefixEndIndex {
            if i == prefixEndIndex - 1, name.children.at(i)?.kind == .dependentGenericSignature {
                optionalGenSig = name.children.at(i)
                break
            }
            _ = printOptional(name.children.at(i))
        }
        if options.contains(.shortenThunk) {
            return
        }
        target.write(" with respect to parameters ")
        _ = printOptional(paramIndices)
        target.write(" and results ")
        _ = printOptional(resultIndices)
        _ = printOptional(options.contains(.displayWhereClauses) ? optionalGenSig : nil, prefix: " with ")
    }

    mutating func printAutoDiffFunctionKind(_ name: Node) {
        guard let kind = name.index else { return }
        switch AutoDiffFunctionKind(kind) {
        case .forward: target.write("forward-mode derivative")
        case .reverse: target.write("reverse-mode derivative")
        case .differential: target.write("differential")
        case .pullback: target.write("pullback")
        default: break
        }
    }

    mutating func printAutoDiffSelfReorderingReabstractionThunk(_ name: Node) {
        target.write("autodiff self-reordering reabstraction thunk ")
        let fromType = name.children.first
        _ = printOptional(options.contains(.shortenThunk) ? fromType : nil, prefix: "for ")
        let toType = name.children.at(1)
        var kindIndex = 2
        var optionalGenSig: Node?
        if name.children.at(kindIndex)?.kind == .dependentGenericSignature {
            optionalGenSig = name.children.at(kindIndex)
            kindIndex += 1
        }
        target.write("for ")
        _ = printOptional(name.children.at(kindIndex))
        _ = printOptional(optionalGenSig, suffix: " ")
        _ = printOptional(fromType, prefix: " from ")
        _ = printOptional(toType, prefix: " to ")
    }

    mutating func printAutoDiffSubsetParametersThunk(_ name: Node) {
        target.write("autodiff subset parameters thunk for ")
        let lastIndex = name.children.count - 1
        let toParamIndices = name.children.at(lastIndex)
        let resultIndices = name.children.at(lastIndex - 1)
        let paramIndices = name.children.at(lastIndex - 2)
        let kind = name.children.at(lastIndex - 3)
        let currentIndex = lastIndex - 4
        _ = printOptional(kind, suffix: " from ")
        if currentIndex == 0 {
            printFirstChild(name)
        } else {
            printSequence(name.children.prefix(currentIndex))
        }
        if options.contains(.shortenThunk) {
            return
        }
        target.write(" with respect to parameters ")
        _ = printOptional(paramIndices)
        target.write(" and results ")
        _ = printOptional(resultIndices)
        target.write(" to parameters ")
        _ = printOptional(toParamIndices)
        _ = printOptional(currentIndex > 0 ? name.children.at(currentIndex) : nil, prefix: " of type ")
    }

    mutating func printIndexSubset(_ name: Node) {
        target.write("{")
        var printedAnyIndex = false
        for (i, c) in (name.text ?? "").enumerated() {
            if c != "S" {
                continue
            }
            if printedAnyIndex {
                target.write(", ")
            }
            target.write("\(i)")
            printedAnyIndex = true
        }
        target.write("}")
    }

    mutating func printBaseWitnessTableAccessor(_ name: Node) {
        _ = printOptional(name.children.at(1), prefix: "base witness table accessor for ")
        _ = printOptional(name.children.at(0), prefix: " in ")
    }

    mutating func printDependentGenericInverseConformanceRequirement(_ name: Node) {
        printFirstChild(name, suffix: ": ~")
        switch name.children.at(1)?.index {
        case 0: target.write("Swift.Copyable")
        case 1: target.write("Swift.Escapable")
        default: target.write("Swift.<bit \(name.children.at(1)?.index ?? 0)>")
        }
    }

    mutating func printDependentGenericSameShapeRequirement(_ name: Node) {
        _ = printOptional(name.children.at(0), suffix: ".shape == ")
        _ = printOptional(name.children.at(1), suffix: ".shape")
    }

    mutating func printConstrainedExistential(_ name: Node) {
        printFirstChild(name, prefix: "any ")
        _ = printOptional(name.children.at(1), prefix: "<", suffix: ">")
    }

    mutating func printName(_ name: Node, asPrefixContext: Bool = false) -> Node? {
        switch name.kind {
        case .accessibleFunctionRecord: target.write(conditional: !options.contains(.shortenThunk), "accessible function runtime record for ")
        case .accessorAttachedMacroExpansion: return printMacro(name: name, asPrefixContext: asPrefixContext, label: "accessor")
        case .accessorFunctionReference: target.write("accessor function at \(name.index ?? 0)")
        case .allocator: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .functionStyle, hasName: false, extraName: (name.children.first?.kind == .class) ? "__allocating_init" : "init")
        case .anonymousContext: printAnonymousContext(name)
        case .anonymousDescriptor: printFirstChild(name, prefix: "anonymous descriptor ")
        case .anyProtocolConformanceList: printChildren(name, prefix: "(", suffix: ")", separator: ", ")
        case .argumentTuple: printFunctionParameters(labelList: nil, parameterType: name, showTypes: options.contains(.showFunctionArgumentTypes))
        case .associatedConformanceDescriptor: printAssociatedConformanceDescriptor(name)
        case .associatedType: return nil
        case .associatedTypeDescriptor: printFirstChild(name, prefix: "associated type descriptor for ")
        case .associatedTypeGenericParamRef: printChildren(name, prefix: "generic parameter reference for associated type ")
        case .associatedTypeMetadataAccessor: printAssociatedTypeMetadataAccessor(name)
        case .associatedTypeRef: printAssociatedTypeRef(name)
        case .associatedTypeWitnessTableAccessor: printAssociatedTypeWitnessTableAccessor(name)
        case .assocTypePath: printChildren(name, separator: ".")
        case .asyncAnnotation: target.write(" async")
        case .asyncAwaitResumePartialFunction: printAsyncAwaitResumePartialFunction(name)
        case .asyncFunctionPointer: target.write("async function pointer to ")
        case .asyncRemoved: printFirstChild(name, prefix: "async demotion of ")
        case .asyncSuspendResumePartialFunction: printAsyncSuspendResumePartialFunction(name)
        case .autoDiffFunction,
             .autoDiffDerivativeVTableThunk: printAutoDiffFunctionOrSimpleThunk(name)
        case .autoDiffFunctionKind: printAutoDiffFunctionKind(name)
        case .autoDiffSelfReorderingReabstractionThunk: printAutoDiffSelfReorderingReabstractionThunk(name)
        case .autoDiffSubsetParametersThunk: printAutoDiffSubsetParametersThunk(name)
        case .backDeploymentFallback: target.write(conditional: !options.contains(.shortenThunk), "back deployment fallback for ")
        case .backDeploymentThunk: target.write(conditional: !options.contains(.shortenThunk), "back deployment thunk for ")
        case .baseConformanceDescriptor: printBaseConformanceDescriptor(name)
        case .baseWitnessTableAccessor: printBaseWitnessTableAccessor(name)
        case .bodyAttachedMacroExpansion: return printMacro(name: name, asPrefixContext: asPrefixContext, label: "body")
        case .boundGenericClass,
             .boundGenericStructure,
             .boundGenericEnum,
             .boundGenericProtocol,
             .boundGenericOtherNominalType,
             .boundGenericTypeAlias: printBoundGeneric(name)
        case .builtinFixedArray: printBuildInFixedArray(name)
        case .builtinTupleType: target.write("Builtin.TheTupleType")
        case .builtinTypeName: target.write(name.text ?? "")
        case .canonicalPrespecializedGenericTypeCachingOnceToken: printFirstChild(name, prefix: "flag for loading of canonical specialized generic type metadata for ")
        case .canonicalSpecializedGenericMetaclass: printFirstChild(name, prefix: "specialized generic metaclass for ")
        case .canonicalSpecializedGenericTypeMetadataAccessFunction: printFirstChild(name, prefix: "canonical specialized generic type metadata accessor for ")
        case .cFunctionPointer,
             .objCBlock,
             .noEscapeFunctionType,
             .escapingAutoClosureType,
             .autoClosureType,
             .thinFunctionType,
             .functionType,
             .escapingObjCBlock,
             .uncurriedFunctionType: printFunctionType(name)
        case .clangType: target.write(name.text ?? "")
        case .class,
             .structure,
             .enum,
             .protocol,
             .typeAlias: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .noType, hasName: true)
        case .classMetadataBaseOffset: printFirstChild(name, prefix: "class metadata base offset for ")
        case .compileTimeConst: printFirstChild(name, prefix: "_const ")
        case .concreteProtocolConformance: printConcreteProtocolConformance(name)
        case .concurrentFunctionType: target.write("@Sendable ")
        case .conformanceAttachedMacroExpansion: return printMacro(name: name, asPrefixContext: asPrefixContext, label: "conformance")
        case .constrainedExistential: printConstrainedExistential(name)
        case .constrainedExistentialRequirementList: printChildren(name, separator: ", ")
        case .constrainedExistentialSelf: target.write("Self")
        case .constructor: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .functionStyle, hasName: name.children.count > 2, extraName: "init")
        case .coroutineContinuationPrototype: printFirstChild(name, prefix: "coroutine continuation prototype for ")
        case .curryThunk: printFirstChild(name, prefix: "curry thunk of ")
        case .deallocator: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .noType, hasName: false, extraName: (name.children.first?.kind == .class) ? "__deallocating_deinit" : "deinit")
        case .declContext: printFirstChild(name)
        case .defaultArgumentInitializer: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .noType, hasName: false, extraName: "default argument \(name.children.at(1)?.index ?? 0)")
        case .defaultAssociatedConformanceAccessor: printDefaultAssociatedConformanceAccessor(name)
        case .defaultAssociatedTypeMetadataAccessor: printFirstChild(name, prefix: "default associated type metadata accessor for ")
        case .dependentAssociatedConformance: printChildren(name, prefix: "dependent associated conformance ")
        case .dependentAssociatedTypeRef: printDependentAssociatedTypeRef(name)
        case .dependentGenericConformanceRequirement: printDependentGenericConformanceRequirement(name)
        case .dependentGenericInverseConformanceRequirement: printDependentGenericInverseConformanceRequirement(name)
        case .dependentGenericLayoutRequirement: printDependentGenericLayoutRequirement(name)
        case .dependentGenericParamCount: return nil
        case .dependentGenericParamPackMarker: break
        case .dependentGenericParamType: target.write(name.text ?? "")
        case .dependentGenericParamValueMarker: break
        case .dependentGenericSameShapeRequirement: printDependentGenericSameShapeRequirement(name)
        case .dependentGenericSameTypeRequirement: printDependentGenericSameTypeRequirement(name)
        case .dependentGenericType: printDependentGenericType(name)
        case .dependentMemberType: printDependentMemberType(name)
        case .dependentProtocolConformanceAssociated: printDependentProtocolConformanceAssociated(name)
        case .dependentProtocolConformanceInherited: printDependentProtocolConformanceInherited(name)
        case .dependentProtocolConformanceRoot: printDependentProtocolConformanceRoot(name)
        case .dependentPseudogenericSignature,
             .dependentGenericSignature: printGenericSignature(name)
        case .destructor: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .noType, hasName: false, extraName: "deinit")
        case .didSet: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "didset")
        case .differentiabilityWitness: printDifferentiabilityWitness(name)
        case .differentiableFunctionType: printDifferentiableFunctionType(name)
        case .directMethodReferenceAttribute: target.write("super ")
        case .directness: name.index.flatMap { Directness(rawValue: $0)?.description }.map { target.write("\($0) ") }
        case .dispatchThunk: printFirstChild(name, prefix: "dispatch thunk of ")
        case .distributedAccessor: target.write(conditional: !options.contains(.shortenThunk), "distributed accessor for ")
        case .distributedThunk: target.write(conditional: !options.contains(.shortenThunk), "distributed thunk ")
        case .droppedArgument: target.write("param\(name.index ?? 0)-removed")
        case .dynamicallyReplaceableFunctionImpl: target.write(conditional: !options.contains(.shortenThunk), "dynamically replaceable thunk for ")
        case .dynamicallyReplaceableFunctionKey: target.write(conditional: !options.contains(.shortenThunk), "dynamically replaceable key for ")
        case .dynamicallyReplaceableFunctionVar: target.write(conditional: !options.contains(.shortenThunk), "dynamically replaceable variable for ")
        case .dynamicAttribute: target.write("dynamic ")
        case .dynamicSelf: target.write("Self")
        case .emptyList: target.write(" empty-list ")
        case .enumCase: printFirstChild(name, prefix: "enum case for ", asPrefixContext: false)
        case .errorType: target.write("<ERROR TYPE>")
        case .existentialMetatype: printExistentialMetatype(name)
        case .explicitClosure: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: options.contains(.showFunctionArgumentTypes) ? .functionStyle : .noType, hasName: false, extraName: "closure #", extraIndex: (name.children.at(1)?.index ?? 0) + 1)
        case .extendedExistentialTypeShape: printExtendedExistentialTypeShape(name)
        case .extension: printExtension(name)
        case .extensionAttachedMacroExpansion: return printMacro(name: name, asPrefixContext: asPrefixContext, label: "extension")
        case .extensionDescriptor: printFirstChild(name, prefix: "extension descriptor ")
        case .fieldOffset: printFieldOffset(name)
        case .firstElementMarker: target.write(" first-element-marker ")
        case .freestandingMacroExpansion: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .noType, hasName: true, extraName: "freestanding macro expansion #", extraIndex: (name.children.at(2)?.index ?? 0) + 1)
        case .fullObjCResilientClassStub: printFirstChild(name, prefix: "full ObjC resilient class stub for ")
        case .fullTypeMetadata: printFirstChild(name, prefix: "full type metadata for ")
        case .function,
             .boundGenericFunction: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .functionStyle, hasName: true)
        case .functionSignatureSpecialization: printSpecializationPrefix(name, description: "function signature specialization")
        case .functionSignatureSpecializationParam: printFunctionSignatureSpecializationParam(name)
        case .functionSignatureSpecializationParamKind: printFunctionSignatureSpecializationParamKind(name)
        case .functionSignatureSpecializationParamPayload: target.write((try? demangleAsNode(name.text ?? "").description) ?? (name.text ?? ""))
        case .functionSignatureSpecializationReturn: printFunctionSignatureSpecializationParam(name)
        case .genericPartialSpecialization: printSpecializationPrefix(name, description: "generic partial specialization", paramPrefix: "Signature = ")
        case .genericPartialSpecializationNotReAbstracted: printSpecializationPrefix(name, description: "generic not re-abstracted partial specialization", paramPrefix: "Signature = ")
        case .genericProtocolWitnessTable: printFirstChild(name, prefix: "generic protocol witness table for ")
        case .genericProtocolWitnessTableInstantiationFunction: printFirstChild(name, prefix: "instantiation function for generic protocol witness table for ")
        case .genericSpecialization,
             .genericSpecializationInResilienceDomain: printSpecializationPrefix(name, description: "generic specialization")
        case .genericSpecializationNotReAbstracted: printSpecializationPrefix(name, description: "generic not re-abstracted specialization")
        case .genericSpecializationParam: printGenericSpecializationParam(name)
        case .genericSpecializationPrespecialized: printSpecializationPrefix(name, description: "generic pre-specialization")
        case .genericTypeMetadataPattern: printFirstChild(name, prefix: "generic type metadata pattern for ")
        case .genericTypeParamDecl: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .noType, hasName: true)
        case .getter: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "getter")
        case .global: printChildren(name)
        case .globalActorFunctionType: printGlobalActorFunctionType(name)
        case .globalGetter: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "getter")
        case .globalVariableOnceDeclList: printGlobalVariableOnceDeclList(name)
        case .globalVariableOnceFunction,
             .globalVariableOnceToken: printGlobalVariableOnceFunction(name)
        case .hasSymbolQuery: target.write("#_hasSymbol query for ")
        case .identifier: target.write(name.text ?? "", type: (name.parent?.kind == .function || name.parent?.kind == .variable) ? .functionDeclaration : .typeName)
        case .implConvention: target.write(name.text ?? "")
        case .implCoroutineKind: printImplCoroutineKind(name)
        case .implDifferentiabilityKind: printImplDifferentiabilityKind(name)
        case .implErasedIsolation: target.write("@isolated(any)")
        case .implErrorResult: printChildren(name, prefix: "@error ", separator: " ")
        case .implParameter,
             .implResult: printImplParameter(name)
        case .implEscaping: target.write("@escaping")
        case .implFunctionAttribute: target.write(name.text ?? "")
        case .implFunctionConvention: printImplFunctionConvention(name)
        case .implFunctionConventionName: break
        case .implFunctionType: printImplFunctionType(name)
        case .implicitClosure: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: options.contains(.showFunctionArgumentTypes) ? .functionStyle : .noType, hasName: false, extraName: "implicit closure #", extraIndex: (name.children.at(1)?.index ?? 0) + 1)
        case .implInvocationSubstitutions: printImplInvocationSubstitutions(name)
        case .implParameterResultDifferentiability: printImplParameterName(name)
        case .implParameterSending: printImplParameterName(name)
        case .implPatternSubstitutions: printImplPatternSubstitutions(name)
        case .implSendingResult: target.write("sending")
        case .implYield: printChildren(name, prefix: "@yields ", separator: " ")
        case .index: target.write("\(name.index ?? 0)")
        case .indexSubset: printIndexSubset(name)
        case .infixOperator: target.write("\(name.text ?? "") infix")
        case .initAccessor: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "init")
        case .initializer: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .noType, hasName: false, extraName: "variable initialization expression")
        case .inlinedGenericFunction: printSpecializationPrefix(name, description: "inlined generic function")
        case .inOut: printFirstChild(name, prefix: "inout ")
        case .integer: target.write("\(name.index ?? 0)")
        case .isolated: printFirstChild(name, prefix: "isolated ")
        case .isolatedAnyFunctionType: target.write("@isolated(any) ")
        case .isolatedDeallocator: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .noType, hasName: false, extraName: name.children.first?.kind == .class ? "__isolated_deallocating_deinit" : "deinit")
        case .isSerialized: target.write("serialized")
        case .iVarDestroyer: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .noType, hasName: false, extraName: "__ivar_destroyer")
        case .iVarInitializer: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .noType, hasName: false, extraName: "__ivar_initializer")
        case .keyPathEqualsThunkHelper,
             .keyPathHashThunkHelper: printKeyPathEqualityThunkHelper(name)
        case .keyPathGetterThunkHelper,
             .keyPathSetterThunkHelper: printKeyPathAccessorThunkHelper(name)
        case .labelList: break
        case .lazyProtocolWitnessTableAccessor: printLazyProtocolWitnesstableAccessor(name)
        case .lazyProtocolWitnessTableCacheVariable: printLazyProtocolWitnesstableCacheVariable(name)
        case .localDeclName: _ = printOptional(name.children.at(1), suffix: " #\((name.children.at(0)?.index ?? 0) + 1)")
        case .macro: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: name.children.count == 3 ? .withColon : .functionStyle, hasName: true)
        case .macroExpansionLoc: printMacroExpansionLoc(name)
        case .macroExpansionUniqueName: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .noType, hasName: true, extraName: "unique name #", extraIndex: (name.children.at(2)?.index ?? 0) + 1)
        case .materializeForSet: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "materializeForSet")
        case .memberAttachedMacroExpansion: return printMacro(name: name, asPrefixContext: asPrefixContext, label: "member")
        case .memberAttributeAttachedMacroExpansion: return printMacro(name: name, asPrefixContext: asPrefixContext, label: "memberAttribute")
        case .mergedFunction: target.write(!options.contains(.shortenThunk) ? "merged " : "")
        case .metaclass: printFirstChild(name, prefix: "metaclass for ")
        case .metadataInstantiationCache: printFirstChild(name, prefix: "metadata instantiation cache for ")
        case .metatype: printMetatype(name)
        case .metatypeRepresentation: target.write(name.text ?? "")
        case .methodDescriptor: printFirstChild(name, prefix: "method descriptor for ")
        case .methodLookupFunction: printFirstChild(name, prefix: "method lookup function for ")
        case .modify2Accessor: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "modify2")
        case .modifyAccessor: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "modify")
        case .module: printModule(name)
        case .moduleDescriptor: printFirstChild(name, prefix: "module descriptor ")
        case .nativeOwningAddressor: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "nativeOwningAddressor")
        case .nativeOwningMutableAddressor: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "nativeOwningMutableAddressor")
        case .nativePinningAddressor: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "nativePinningAddressor")
        case .nativePinningMutableAddressor: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "nativePinningMutableAddressor")
        case .negativeInteger: target.write("-\(name.index ?? 0)")
        case .noDerivative: printFirstChild(name, prefix: "@noDerivative ")
        case .nominalTypeDescriptor: printFirstChild(name, prefix: "nominal type descriptor for ")
        case .nominalTypeDescriptorRecord: printFirstChild(name, prefix: "nominal type descriptor runtime record for ")
        case .noncanonicalSpecializedGenericTypeMetadata: printFirstChild(name, prefix: "noncanonical specialized generic type metadata for ")
        case .noncanonicalSpecializedGenericTypeMetadataCache: printFirstChild(name, prefix: "cache variable for noncanonical specialized generic type metadata for ")
        case .nonObjCAttribute: target.write("@nonobjc ")
        case .nonUniqueExtendedExistentialTypeShapeSymbolicReference: target.writeHex(prefix: "non-unique existential shape symbolic reference 0x", name.index ?? 0)
        case .number: target.write("\(name.index ?? 0)")
        case .objCAsyncCompletionHandlerImpl,
             .predefinedObjCAsyncCompletionHandlerImpl: printObjCAsyncCompletionHandlerImpl(name)
        case .objCAttribute: target.write("@objc ")
        case .objCMetadataUpdateFunction: printFirstChild(name, prefix: "ObjC metadata update function for ")
        case .objCResilientClassStub: printFirstChild(name, prefix: "ObjC resilient class stub for ")
        case .objectiveCProtocolSymbolicReference: target.writeHex(prefix: "objective-c protocol symbolic reference 0x", name.index ?? 0)
        case .opaqueReturnType: target.write("some")
        case .opaqueReturnTypeIndex: break
        case .opaqueReturnTypeOf: printChildren(name, prefix: "<<opaque return type of ", suffix: ">>")
        case .opaqueReturnTypeParent: break
        case .opaqueType: printOpaqueType(name)
        case .opaqueTypeDescriptor: printFirstChild(name, prefix: "opaque type descriptor for ")
        case .opaqueTypeDescriptorAccessor: printFirstChild(name, prefix: "opaque type descriptor accessor for ")
        case .opaqueTypeDescriptorAccessorImpl: printFirstChild(name, prefix: "opaque type descriptor accessor impl for ")
        case .opaqueTypeDescriptorAccessorKey: printFirstChild(name, prefix: "opaque type descriptor accessor key for ")
        case .opaqueTypeDescriptorAccessorVar: printFirstChild(name, prefix: "opaque type descriptor accessor var for ")
        case .opaqueTypeDescriptorRecord: printFirstChild(name, prefix: "opaque type descriptor runtime record for ")
        case .opaqueTypeDescriptorSymbolicReference: target.writeHex(prefix: "opaque type symbolic reference 0x", name.index ?? 0)
        case .otherNominalType: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .noType, hasName: true)
        case .outlinedAssignWithCopy,
             .outlinedAssignWithCopyNoValueWitness: printFirstChild(name, prefix: "outlined assign with copy of ")
        case .outlinedAssignWithTake,
             .outlinedAssignWithTakeNoValueWitness: printFirstChild(name, prefix: "outlined assign with take of ")
        case .outlinedBridgedMethod: target.write("outlined bridged method (\(name.text ?? "")) of ")
        case .outlinedConsume: printFirstChild(name, prefix: "outlined consume of ")
        case .outlinedCopy: printFirstChild(name, prefix: "outlined copy of ")
        case .outlinedDestroy,
             .outlinedDestroyNoValueWitness: printFirstChild(name, prefix: "outlined destroy of ")
        case .outlinedEnumGetTag: printFirstChild(name, prefix: "outlined enum get tag of ")
        case .outlinedEnumProjectDataForLoad: printFirstChild(name, prefix: "outlined enum project data for load of ")
        case .outlinedEnumTagStore: printFirstChild(name, prefix: "outlined enum tag store of ")
        case .outlinedInitializeWithCopy,
             .outlinedInitializeWithCopyNoValueWitness: printFirstChild(name, prefix: "outlined init with copy of ")
        case .outlinedInitializeWithTake: printFirstChild(name, prefix: "outlined init with take of ")
        case .outlinedReadOnlyObject: target.write("outlined read-only object #\(name.index ?? 0) of ")
        case .outlinedRelease: printFirstChild(name, prefix: "outlined release of ")
        case .outlinedRetain: printFirstChild(name, prefix: "outlined retain of ")
        case .outlinedVariable: target.write("outlined variable #\(name.index ?? 0) of ")
        case .owned: printFirstChild(name, prefix: "__owned ")
        case .owningAddressor: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "owningAddressor")
        case .owningMutableAddressor: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "owningMutableAddressor")
        case .pack: printChildren(name, prefix: "Pack{", suffix: "}", separator: ", ")
        case .packElement: printFirstChild(name, prefix: "/* level: \(name.children.at(1)?.index ?? 0) */ each ")
        case .packElementLevel: break
        case .packExpansion: printFirstChild(name, prefix: "repeat ")
        case .packProtocolConformance: printChildren(name, prefix: "pack protocol conformance ")
        case .partialApplyForwarder: printPartialApplyForwarder(name)
        case .partialApplyObjCForwarder: printPartialApplyObjCForwarder(name)
        case .peerAttachedMacroExpansion: return printMacro(name: name, asPrefixContext: asPrefixContext, label: "peer")
        case .postfixOperator: target.write("\(name.text ?? "") postfix")
        case .prefixOperator: target.write("\(name.text ?? "") prefix")
        case .privateDeclName: printPrivateDeclName(name)
        case .propertyDescriptor: printFirstChild(name, prefix: "property descriptor for ")
        case .propertyWrapperBackingInitializer: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .noType, hasName: false, extraName: "property wrapper backing initializer")
        case .propertyWrapperInitFromProjectedValue: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .noType, hasName: false, extraName: "property wrapper init from projected value")
        case .protocolConformance: printProtocolConformance(name)
        case .protocolConformanceDescriptor: printFirstChild(name, prefix: "protocol conformance descriptor for ")
        case .protocolConformanceDescriptorRecord: printFirstChild(name, prefix: "protocol conformance descriptor runtime record for ")
        case .protocolConformanceRefInOtherModule: printChildren(name, prefix: "protocol conformance ref (retroactive) ")
        case .protocolConformanceRefInProtocolModule: printChildren(name, prefix: "protocol conformance ref (protocol's module) ")
        case .protocolConformanceRefInTypeModule: printChildren(name, prefix: "protocol conformance ref (type's module) ")
        case .protocolDescriptor: printFirstChild(name, prefix: "protocol descriptor for ")
        case .protocolDescriptorRecord: printFirstChild(name, prefix: "protocol descriptor runtime record for ")
        case .protocolList: printProtocolList(name)
        case .protocolListWithAnyObject: printProtocolListWithAnyObject(name)
        case .protocolListWithClass: printProtocolListWithClass(name)
        case .protocolRequirementsBaseDescriptor: printFirstChild(name, prefix: "protocol requirements base descriptor for ")
        case .protocolSelfConformanceDescriptor: printFirstChild(name, prefix: "protocol self-conformance descriptor for ")
        case .protocolSelfConformanceWitness: printFirstChild(name, prefix: "protocol self-conformance witness for ")
        case .protocolSelfConformanceWitnessTable: printFirstChild(name, prefix: "protocol self-conformance witness table for ")
        case .protocolSymbolicReference: target.write("protocol symbolic reference \("0x" + String(name.index ?? 0, radix: 16, uppercase: true))")
        case .protocolWitness: printProtocolWitness(name)
        case .protocolWitnessTable: printFirstChild(name, prefix: "protocol witness table for ")
        case .protocolWitnessTableAccessor: printFirstChild(name, prefix: "protocol witness table accessor for ")
        case .protocolWitnessTablePattern: printFirstChild(name, prefix: "protocol witness table pattern for ")
        case .reabstractionThunk,
             .reabstractionThunkHelper: printReabstractionThunk(name)
        case .reabstractionThunkHelperWithGlobalActor: printReabstracctionThunkHelperWithGlobalActor(name)
        case .reabstractionThunkHelperWithSelf: printReabstractionThunkHelperWithSelf(name)
        case .read2Accessor: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "read2")
        case .readAccessor: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "read")
        case .reflectionMetadataAssocTypeDescriptor: printFirstChild(name, prefix: "reflection metadata associated type descriptor ")
        case .reflectionMetadataBuiltinDescriptor: printFirstChild(name, prefix: "reflection metadata builtin descriptor ")
        case .reflectionMetadataFieldDescriptor: printFirstChild(name, prefix: "reflection metadata field descriptor ")
        case .reflectionMetadataSuperclassDescriptor: printFirstChild(name, prefix: "reflection metadata superclass descriptor ")
        case .relatedEntityDeclName: printFirstChild(name, prefix: "related decl '\(name.text ?? "")' for ")
        case .resilientProtocolWitnessTable: printFirstChild(name, prefix: "resilient protocol witness table for ")
        case .retroactiveConformance: printRetroactiveConformance(name)
        case .returnType: printReturnType(name)
        case .sending: printFirstChild(name, prefix: "sending ")
        case .sendingResultFunctionType: target.write("sending ")
        case .setter: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "setter")
        case .shared: printFirstChild(name, prefix: "__shared ")
        case .silBoxImmutableField,
             .silBoxMutableField: printFirstChild(name, prefix: name.kind == .silBoxImmutableField ? "let " : "var ")
        case .silBoxLayout: printSequence(name.children, prefix: "{\(name.children.isEmpty ? "" : " ")", suffix: " }", separator: ", ")
        case .silBoxType: printFirstChild(name, prefix: "@box ")
        case .silBoxTypeWithLayout: printSilBoxTypeWithLayout(name)
        case .silPackDirect: printChildren(name, prefix: "@direct Pack{", suffix: "}", separator: ", ")
        case .silPackIndirect: printChildren(name, prefix: "@indirect Pack{", suffix: "}", separator: ", ")
        case .silThunkHopToMainActorIfNeeded: printFirstChild(name, prefix: "hop to main actor thunk of ")
        case .silThunkIdentity: printFirstChild(name, prefix: "identity thunk of ")
        case .specializationPassID: target.write("\(name.index ?? 0)")
        case .static: printFirstChild(name, prefix: "static ")
        case .subscript: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .functionStyle, hasName: true, overwriteName: "subscript")
        case .suffix: printSuffix(name)
        case .sugaredArray: printFirstChild(name, prefix: "[", suffix: "]")
        case .sugaredDictionary: printSugaredDictionary(name)
        case .sugaredOptional: printSugaredOptional(name)
        case .sugaredParen: printFirstChild(name, prefix: "(", suffix: ")")
        case .symbolicExtendedExistentialType: printSymbolicExtendedExistentialType(name)
        case .throwsAnnotation: target.write(" throws")
        case .tuple: printChildren(name, prefix: "(", suffix: ")", separator: ", ")
        case .tupleElement: printTupleElement(name)
        case .tupleElementName: target.write("\(name.text ?? ""): ")
        case .type: printFirstChild(name)
        case .typedThrowsAnnotation: printTypeThrowsAnnotation(name)
        case .typeList: printChildren(name)
        case .typeMangling: printFirstChild(name)
        case .typeMetadata: printFirstChild(name, prefix: "type metadata for ")
        case .typeMetadataAccessFunction: printFirstChild(name, prefix: "type metadata accessor for ")
        case .typeMetadataCompletionFunction: printFirstChild(name, prefix: "type metadata completion function for ")
        case .typeMetadataDemanglingCache: printFirstChild(name, prefix: "demangling cache variable for type metadata for ")
        case .typeMetadataInstantiationCache: printFirstChild(name, prefix: "type metadata instantiation cache for ")
        case .typeMetadataInstantiationFunction: printFirstChild(name, prefix: "type metadata instantiation cache for ")
        case .typeMetadataLazyCache: printFirstChild(name, prefix: "lazy cache variable for type metadata for ")
        case .typeMetadataSingletonInitializationCache: printFirstChild(name, prefix: "type metadata singleton initialization cache for ")
        case .typeSymbolicReference: target.write("type symbolic reference \("0x" + String(name.index ?? 0, radix: 16, uppercase: true))")
        case .uniquable: printFirstChild(name, prefix: "uniquable ")
        case .uniqueExtendedExistentialTypeShapeSymbolicReference: target.writeHex(prefix: "non-unique existential shape symbolic reference 0x", name.index ?? 0)
        case .unknownIndex: target.write("unknown index")
        case .unmanaged: printFirstChild(name, prefix: "unowned(unsafe) ")
        case .unowned: printFirstChild(name, prefix: "unowned ")
        case .unsafeAddressor: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "unsafeAddressor")
        case .unsafeMutableAddressor: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "unsafeMutableAddressor")
        case .valueWitness: printValueWitness(name)
        case .valueWitnessTable: printFirstChild(name, prefix: "value witness table for ")
        case .variable: return printEntity(name, asPrefixContext: asPrefixContext, typePrinting: .withColon, hasName: true)
        case .variadicMarker: target.write(" variadic-marker ")
        case .vTableAttribute: target.write("override ")
        case .vTableThunk: printVTableThunk(name)
        case .weak: printFirstChild(name, prefix: "weak ")
        case .willSet: return printAbstractStorage(name.children.first, asPrefixContext: asPrefixContext, extraName: "willset")
        }

        return nil
    }

    mutating func printAbstractStorage(_ name: Node?, asPrefixContext: Bool, extraName: String) -> Node? {
        guard let n = name else { return nil }
        switch n.kind {
        case .variable: return printEntity(n, asPrefixContext: asPrefixContext, typePrinting: .withColon, hasName: true, extraName: extraName)
        case .subscript: return printEntity(n, asPrefixContext: asPrefixContext, typePrinting: .withColon, hasName: false, extraName: extraName, extraIndex: nil, overwriteName: "subscript")
        default: return nil
        }
    }

    mutating func printEntityType(name: Node, type: Node, genericFunctionTypeList: Node?) {
        let labelList = name.children.first(where: { $0.kind == .labelList })
        if labelList != nil || genericFunctionTypeList != nil {
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
        } else {
            _ = printName(type)
        }
    }

    mutating func printEntity(_ name: Node, asPrefixContext: Bool, typePrinting: TypePrinting, hasName: Bool, extraName: String? = nil, extraIndex: UInt64? = nil, overwriteName: String? = nil) -> Node? {
        var genericFunctionTypeList: Node?
        var name = name
        if name.kind == .boundGenericFunction, let first = name.children.at(0), let second = name.children.at(1) {
            name = first
            genericFunctionTypeList = second
        }

        let multiWordName = extraName?.contains(" ") == true || (hasName && name.children.at(1)?.kind == .localDeclName)
        if asPrefixContext && (typePrinting != .noType || multiWordName) {
            return name
        }

        guard let context = name.children.first else { return nil }
        var postfixContext: Node?
        if shouldPrintContext(context) {
            if multiWordName {
                postfixContext = context
            } else {
                let currentPos = target.count
                postfixContext = printName(context, asPrefixContext: true)
                if target.count != currentPos {
                    target.write(".")
                }
            }
        }

        var extraNameConsumed = extraName == nil
        if hasName || overwriteName != nil {
            if !extraNameConsumed, multiWordName {
                target.write(extraName ?? "")
                if let extraIndex {
                    target.write("\(extraIndex)")
                }
                target.write(" of ")
                extraNameConsumed = true
            }
            let currentPos = target.count
            if let o = overwriteName {
                target.write(o)
            } else {
                if let one = name.children.at(1) {
                    if one.kind != .privateDeclName {
                        _ = printName(one)
                    }
                    if let pdn = name.children.first(where: { $0.kind == .privateDeclName }) {
                        _ = printName(pdn)
                    }
                }
            }
            if target.count != currentPos, !extraNameConsumed {
                target.write(".")
            }
        }
        if !extraNameConsumed {
            target.write(extraName ?? "")
            if let ei = extraIndex {
                target.write("\(ei)")
            }
        }
        if typePrinting != .noType {
            guard var type = name.children.first(where: { $0.kind == .type }) else { return nil }
            if type.kind != .type {
                guard let nextType = name.children.at(2) else { return nil }
                type = nextType
            }
            guard type.kind == .type, let firstChild = type.children.first else { return nil }
            type = firstChild
            var typePr = typePrinting
            if typePr == .functionStyle {
                var t = type
                while t.kind == .dependentGenericType, let next = t.children.at(1)?.children.at(0) {
                    t = next
                }
                switch t.kind {
                case .functionType,
                     .noEscapeFunctionType,
                     .uncurriedFunctionType,
                     .cFunctionPointer,
                     .thinFunctionType: break
                default: typePr = .withColon
                }
            }
            if typePr == .withColon {
                if options.contains(.displayEntityTypes) {
                    target.write(" : ")
                    printEntityType(name: name, type: type, genericFunctionTypeList: genericFunctionTypeList)
                }
            } else {
                if multiWordName || type.needSpaceBeforeType {
                    target.write(" ")
                }
                printEntityType(name: name, type: type, genericFunctionTypeList: genericFunctionTypeList)
            }
        }
        if !asPrefixContext, let pfc = postfixContext {
            switch name.kind {
            case .defaultArgumentInitializer,
                 .initializer,
                 .propertyWrapperBackingInitializer,
                 .propertyWrapperInitFromProjectedValue:
                target.write(" of ")
            default:
                target.write(" in ")
            }
            _ = printName(pfc)
            return nil
        }
        return postfixContext
    }

    mutating func printSpecializationPrefix(_ name: Node, description: String, paramPrefix: String = "") {
        if !options.contains(.displayGenericSpecializations) {
            if !specializationPrefixPrinted {
                target.write("specialized ")
                specializationPrefixPrinted = true
            }
            return
        }
        target.write("\(description) <")
        var separator = ""
        var argNum = 0
        for c in name.children {
            switch c.kind {
            case .specializationPassID,
                 .droppedArgument: break
            case .isSerialized:
                target.write(separator)
                separator = ", "
                _ = printName(c)
            default:
                if !c.children.isEmpty {
                    target.write(separator)
                    target.write(paramPrefix)
                    separator = ", "
                    switch c.kind {
                    case .functionSignatureSpecializationParam:
                        target.write("Arg[\(argNum)] = ")
                        printFunctionSignatureSpecializationParam(c)
                    case .functionSignatureSpecializationReturn:
                        target.write("Return = ")
                        printFunctionSignatureSpecializationParam(c)
                    default:
                        _ = printName(c)
                    }
                }
                argNum += 1
            }
        }
        target.write("> of ")
    }

    mutating func printFunctionParameters(labelList: Node?, parameterType: Node, showTypes: Bool) {
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
                target.write(label.kind == .identifier ? (label.text ?? "") : "_", type: .functionDeclaration)
                target.write(":")
                if showTypes {
                    target.write(" ")
                }
            } else if !showTypes {
                if let label = tuple.element.children.first(where: { $0.kind == .tupleElementName }) {
                    target.write(label.text ?? "", type: .functionDeclaration)
                    target.write(":")
                } else {
                    target.write("_", type: .functionDeclaration)
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

    mutating func printConventionWithMangledCType(_ name: Node, label: String) {
        target.write("@convention(\(label)")
        if let firstChild = name.children.first, firstChild.kind == .clangType {
            target.write(", mangledCType: \"")
            _ = printName(firstChild)
            target.write("\"")
        }
        target.write(") ")
    }

    mutating func printFunctionType(labelList: Node? = nil, _ name: Node) {
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

        if isSendable {
            target.write("@Sendable ")
        }

        guard let parameterType = name.children.at(argIndex) else { return }
        printFunctionParameters(labelList: labelList, parameterType: parameterType, showTypes: options.contains(.showFunctionArgumentTypes))
        if !options.contains(.showFunctionArgumentTypes) {
            return
        }
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

    mutating func printBoundGenericNoSugar(_ name: Node) {
        guard let typeList = name.children.at(1) else { return }
        printFirstChild(name)
        printChildren(typeList, prefix: "<", suffix: ">", separator: ", ")
    }

    func findSugar(_ name: Node) -> SugarType {
        guard let firstChild = name.children.at(0) else { return .none }
        if name.children.count == 1, firstChild.kind == .type { return findSugar(firstChild) }

        guard name.kind == .boundGenericEnum || name.kind == .boundGenericStructure else { return .none }
        guard let secondChild = name.children.at(1) else { return .none }
        guard name.children.count == 2 else { return .none }

        guard let unboundType = firstChild.children.first, unboundType.children.count > 1 else { return .none }
        let typeArgs = secondChild

        let c0 = unboundType.children.at(0)
        let c1 = unboundType.children.at(1)

        if name.kind == .boundGenericEnum {
            if c1?.isIdentifier(desired: "Optional") == true && typeArgs.children.count == 1 && c0?.isSwiftModule == true {
                return .optional
            }
            if c1?.isIdentifier(desired: "ImplicitlyUnwrappedOptional") == true && typeArgs.children.count == 1 && c0?.isSwiftModule == true {
                return .implicitlyUnwrappedOptional
            }
            return .none
        }
        if c1?.isIdentifier(desired: "Array") == true && typeArgs.children.count == 1 && c0?.isSwiftModule == true {
            return .array
        }
        if c1?.isIdentifier(desired: "Dictionary") == true && typeArgs.children.count == 2 && c0?.isSwiftModule == true {
            return .dictionary
        }
        return .none
    }

    mutating func printBoundGeneric(_ name: Node) {
        guard name.children.count >= 2 else { return }
        guard name.children.count == 2, options.contains(.synthesizeSugarOnTypes), name.kind != .boundGenericClass else {
            printBoundGenericNoSugar(name)
            return
        }

        if name.kind == .boundGenericProtocol {
            _ = printOptional(name.children.at(1))
            _ = printOptional(name.children.at(0), prefix: " as ")
            return
        }

        let sugarType = findSugar(name)
        switch sugarType {
        case .optional,
             .implicitlyUnwrappedOptional:
            if let type = name.children.at(1)?.children.at(0) {
                let needParens = !type.isSimpleType
                _ = printOptional(type, prefix: needParens ? "(" : "", suffix: needParens ? ")" : "")
                target.write(sugarType == .optional ? "?" : "!")
            }
        case .array,
             .dictionary:
            _ = printOptional(name.children.at(1)?.children.at(0), prefix: "[")
            if sugarType == .dictionary {
                _ = printOptional(name.children.at(1)?.children.at(1), prefix: " : ")
            }
            target.write("]")
        default: printBoundGenericNoSugar(name)
        }
    }

    mutating func printImplFunctionType(_ name: Node) {
        enum State: Int { case attrs, inputs, results }
        var curState: State = .attrs
        var patternSubs: Node?
        var invocationSubs: Node?
        var sendingResult: Node?
        let transitionTo = { (printer: inout NodePrinter, newState: State) in
            while curState != newState {
                switch curState {
                case .attrs:
                    if let patternSubs {
                        printer.printFirstChild(patternSubs, prefix: "@substituted ", suffix: " ")
                    }
                    printer.target.write("(")
                case .inputs:
                    printer.target.write(") -> ")
                    if let sendingResult {
                        _ = printer.printName(sendingResult)
                        printer.target.write(" ")
                    }
                    printer.target.write("(")
                case .results: break
                }
                guard let nextState = State(rawValue: curState.rawValue + 1) else { break }
                curState = nextState
            }
        }
        childLoop: for c in name.children {
            if c.kind == .implParameter {
                if curState == .inputs {
                    target.write(", ")
                }
                transitionTo(&self, .inputs)
                _ = printName(c)
            } else if c.kind == .implResult || c.kind == .implYield || c.kind == .implErrorResult {
                if curState == .results {
                    target.write(", ")
                }
                transitionTo(&self, .results)
                _ = printName(c)
            } else if c.kind == .implPatternSubstitutions {
                patternSubs = c
            } else if c.kind == .implInvocationSubstitutions {
                invocationSubs = c
            } else if c.kind == .implSendingResult {
                sendingResult = c

            } else {
                _ = printName(c)
                target.write(" ")
            }
        }
        transitionTo(&self, .results)
        target.write(")")
        if let patternSubs, let second = patternSubs.children.at(1) {
            printChildren(second, prefix: " for <", suffix: ">")
        }
        if let invocationSubs, let second = invocationSubs.children.at(0) {
            printChildren(second, prefix: " for <", suffix: ">")
        }
    }

    mutating func quotedString(_ value: String) {
        target.write("\"")
        for c in value.unicodeScalars {
            switch c {
            case "\\": target.write("\\\\")
            case "\t": target.write("\\t")
            case "\n": target.write("\\n")
            case "\r": target.write("\\r")
            case "\"": target.write("\\\"")
            case "\0": target.write("\\0")
            default:
                if c < UnicodeScalar(0x20) || c == UnicodeScalar(0x7F) {
                    target.write("\\x")
                    target.write(String(describing: ((c.value >> 4) > 9) ? UnicodeScalar(c.value + UnicodeScalar("A").value) : UnicodeScalar(c.value + UnicodeScalar("0").value)))
                } else {
                    target.write(String(c))
                }
            }
        }
        target.write("\"")
    }
}
