import Demangling

protocol DependentGenericNodePrintable: NodePrintable {
    var isProtocol: Bool { get }
    mutating func printNameInDependentGeneric(_ name: Node, context: Context?) -> Bool
    mutating func printGenericSignature(_ name: Node)
    mutating func printDependentGenericConformanceRequirement(_ name: Node)
    mutating func printDependentGenericLayoutRequirement(_ name: Node)
    mutating func printDependentAssociatedTypeRef(_ name: Node)
    mutating func printDependentGenericParamType(_ name: Node)
    mutating func printDependentGenericSameTypeRequirement(_ name: Node)
    mutating func printDependentGenericType(_ name: Node)
    mutating func printDependentMemberType(_ name: Node)
    mutating func printDependentGenericInverseConformanceRequirement(_ name: Node)
    mutating func printDependentGenericParamName(_ name: String)
}

extension DependentGenericNodePrintable {
    mutating func printNameInDependentGeneric(_ name: Node, context: Context?) -> Bool {
        switch name.kind {
        case .dependentGenericParamType:
            printDependentGenericParamType(name)
        case .dependentAssociatedTypeRef:
            printDependentAssociatedTypeRef(name)
        case .dependentGenericConformanceRequirement:
            printDependentGenericConformanceRequirement(name)
        case .dependentGenericLayoutRequirement:
            printDependentGenericLayoutRequirement(name)
        case .dependentGenericSameTypeRequirement:
            printDependentGenericSameTypeRequirement(name)
        case .dependentGenericType:
            printDependentGenericType(name)
        case .dependentMemberType:
            printDependentMemberType(name)
        case .dependentGenericSignature:
            printGenericSignature(name)
        case .dependentGenericInverseConformanceRequirement:
            printDependentGenericInverseConformanceRequirement(name)
        case .dependentGenericParamPackMarker:
            break
        default:
            return false
        }
        return true
    }

    mutating func printDependentAssociatedTypeRef(_ name: Node) {
        _ = printOptional(name.children.at(1), suffix: ".")
        printFirstChild(name)
    }

    mutating func printDependentGenericParamType(_ name: Node) {
        printDependentGenericParamName(name.text ?? "")
    }

    mutating func printDependentGenericParamName(_ name: String) {
        if isProtocol, name == "A" {
            target.write("Self", context: .context(state: .printKeyword))
        } else {
            target.write(name)
        }
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

        let depths = name.parent?.findGenericParamsDepth()

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
                    target.write("each", context: .context(state: .printKeyword))
                    target.writeSpace()
                }

                let value = isGenericParamValue(UInt64(gpDepth), UInt64(index))
                if value != nil {
                    target.write("let", context: .context(state: .printKeyword))
                    target.writeSpace()
                }

                printDependentGenericParamName(genericParameterName(depth: depths?[index.cast()] ?? gpDepth.cast(), index: index.cast()))

                if let value {
                    target.write(": ")
                    _ = printName(value)
                }
            }
        }

//        if firstRequirement != name.children.count {
//            if options.contains(.displayWhereClauses) {
//                target.write(" where ")
//                printSequence(name.children.dropFirst(firstRequirement), separator: ", ")
//            }
//        }
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
        case "U": target.write("_UnknownLayout", context: .context(state: .printType))
        case "R": target.write("_RefCountedObject", context: .context(state: .printType))
        case "N": target.write("_NativeRefCountedObject", context: .context(state: .printType))
        case "C": target.write("AnyObject", context: .context(state: .printType))
        case "D": target.write("_NativeClass", context: .context(state: .printType))
        case "T": target.write("_Trivial", context: .context(state: .printType))
        case "E",
             "e": target.write("_Trivial", context: .context(state: .printType))
        case "M",
             "m": target.write("_TrivialAtMost", context: .context(state: .printType))
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

    mutating func printDependentGenericInverseConformanceRequirement(_ name: Node) {
        printFirstChild(name, suffix: ": ~")
        switch name.children.at(1)?.index {
        case 0: target.write("Swift.Copyable", context: .context(state: .printType))
        case 1: target.write("Swift.Escapable", context: .context(state: .printType))
        default: target.write("Swift.<bit \(name.children.at(1)?.index ?? 0)>")
        }
    }
}
