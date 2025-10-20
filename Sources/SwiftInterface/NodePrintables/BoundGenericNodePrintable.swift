import Demangling

protocol BoundGenericNodePrintable: NodePrintable {
    mutating func printNameInBoundGeneric(_ name: Node, context: Context?) -> Bool
    mutating func printBoundGeneric(_ name: Node)
    mutating func printBoundGenericNoSugar(_ name: Node)
}

extension BoundGenericNodePrintable {
    mutating func printNameInBoundGeneric(_ name: Node, context: Context?) -> Bool {
        switch name.kind {
        case .boundGenericClass,
             .boundGenericStructure,
             .boundGenericEnum,
             .boundGenericProtocol,
             .boundGenericOtherNominalType,
             .boundGenericTypeAlias:
            printBoundGeneric(name)
            return true
        default:
            return false
        }
    }

    mutating func printBoundGeneric(_ name: Node) {
        guard name.children.count >= 2 else { return }
        guard name.children.count == 2, name.kind != .boundGenericClass else {
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
}
