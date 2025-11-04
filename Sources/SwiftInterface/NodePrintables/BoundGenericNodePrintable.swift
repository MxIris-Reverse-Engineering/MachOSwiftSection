import Demangling

protocol BoundGenericNodePrintable: NodePrintable {
    mutating func printNameInBoundGeneric(_ name: Node, context: Context?) async -> Bool
    mutating func printBoundGeneric(_ name: Node) async
    mutating func printBoundGenericNoSugar(_ name: Node) async
}

extension BoundGenericNodePrintable {
    mutating func printNameInBoundGeneric(_ name: Node, context: Context?) async -> Bool {
        switch name.kind {
        case .boundGenericClass,
             .boundGenericStructure,
             .boundGenericEnum,
             .boundGenericProtocol,
             .boundGenericOtherNominalType,
             .boundGenericTypeAlias:
            await printBoundGeneric(name)
            return true
        default:
            return false
        }
    }

    mutating func printBoundGeneric(_ name: Node) async {
        guard name.children.count >= 2 else { return }
        guard name.children.count == 2, name.kind != .boundGenericClass else {
            await printBoundGenericNoSugar(name)
            return
        }

        if name.kind == .boundGenericProtocol {
            _ = await printOptional(name.children.at(1))
            _ = await printOptional(name.children.at(0), prefix: " as ")
            return
        }

        let sugarType = findSugar(name)
        switch sugarType {
        case .optional,
             .implicitlyUnwrappedOptional:
            if let type = name.children.at(1)?.children.at(0) {
                let needParens = !type.isSimpleType
                _ = await printOptional(type, prefix: needParens ? "(" : "", suffix: needParens ? ")" : "")
                target.write(sugarType == .optional ? "?" : "!")
            }
        case .array,
             .dictionary:
            _ = await printOptional(name.children.at(1)?.children.at(0), prefix: "[")
            if sugarType == .dictionary {
                _ = await printOptional(name.children.at(1)?.children.at(1), prefix: " : ")
            }
            target.write("]")
        default: await printBoundGenericNoSugar(name)
        }
    }

    mutating func printBoundGenericNoSugar(_ name: Node) async {
        guard let typeList = name.children.at(1) else { return }
        await printFirstChild(name)
        await printChildren(typeList, prefix: "<", suffix: ">", separator: ", ")
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
