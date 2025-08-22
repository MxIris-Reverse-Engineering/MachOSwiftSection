import Demangle

protocol DependentGenericNodePrintable: NodePrintable {
    mutating func printNameInDependentGeneric(_ name: Node) -> Bool
    mutating func printGenericSignature(_ name: Node)
    mutating func printDependentGenericConformanceRequirement(_ name: Node)
    mutating func printDependentGenericLayoutRequirement(_ name: Node)
}

extension DependentGenericNodePrintable {
    mutating func printNameInDependentGeneric(_ name: Node) -> Bool {
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
        target.write(name.text ?? "")
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

    private func findGenericParamsDepth(_ name: Node) -> [Int: Int]? {
        guard let _: Int = name.children.first(of: .dependentGenericParamCount)?.index?.cast(), let parent = name.parent else { return nil }

        var depths: [Int: Int] = [:]

        for child in parent.preorder() {
            guard child.kind == .dependentGenericParamType else { continue }
            guard let depth: Int = child.children.at(0)?.index?.cast() else { continue }
            guard let index: Int = child.children.at(1)?.index?.cast() else { continue }

            if let currentDepth = depths[index] {
                depths[index] = max(currentDepth, depth)
            } else {
                depths[index] = depth
            }
        }

        return depths
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

        let depths = findGenericParamsDepth(name)

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

                target.write(Self.genericParameterName(depth: UInt64(depths?[index.cast()] ?? gpDepth), index: UInt64(index)))

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
}
