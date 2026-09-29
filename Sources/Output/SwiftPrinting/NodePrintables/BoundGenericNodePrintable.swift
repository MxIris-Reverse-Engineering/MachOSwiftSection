import SwiftDeclaration
import Demangling

protocol BoundGenericNodePrintable: NodePrintable {
    mutating func printNameInBoundGeneric(_ name: Node) async -> Bool
    mutating func printBoundGeneric(_ name: Node) async
    mutating func printBoundGenericNoSugar(_ name: Node) async
}

extension BoundGenericNodePrintable {
    mutating func printNameInBoundGeneric(_ name: Node) async -> Bool {
        switch name.kind {
        case .boundGenericClass,
             .boundGenericStructure,
             .boundGenericEnum,
             .boundGenericProtocol,
             .boundGenericOtherNominalType,
             .boundGenericTypeAlias:
            // Barrier scope: angle brackets, commas, and sugar punctuation
            // written by the bound-generic printer belong to no type
            // reference; the base type and each argument push their own
            // scopes when they recurse through the nominal cases.
            target.pushTypeReferenceScope(nil)
            await printBoundGeneric(name)
            target.popTypeReferenceScope()
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
            await printOptional(name.children.at(1))
            await printOptional(name.children.at(0), prefix: " as ")
            return
        }

        let sugarType = findSugar(name)
        switch sugarType {
        case .optional,
             .implicitlyUnwrappedOptional:
            if let type = name.children.at(1)?.children.at(0) {
                let needParens = !type.isSimpleType
                await printOptional(type, prefix: needParens ? "(" : "", suffix: needParens ? ")" : "")
                target.write(sugarType == .optional ? "?" : "!")
            }
        case .array,
             .dictionary:
            await printOptional(name.children.at(1)?.children.at(0), prefix: "[")
            if sugarType == .dictionary {
                await printOptional(name.children.at(1)?.children.at(1), prefix: " : ")
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
        let typeArguments = secondChild

        let moduleNode = unboundType.children.at(0)
        let identifierNode = unboundType.children.at(1)

        if name.kind == .boundGenericEnum {
            if identifierNode?.isIdentifier(desired: "Optional") == true && typeArguments.children.count == 1 && moduleNode?.isSwiftModule == true {
                return .optional
            }
            if identifierNode?.isIdentifier(desired: "ImplicitlyUnwrappedOptional") == true && typeArguments.children.count == 1 && moduleNode?.isSwiftModule == true {
                return .implicitlyUnwrappedOptional
            }
            return .none
        }
        if identifierNode?.isIdentifier(desired: "Array") == true && typeArguments.children.count == 1 && moduleNode?.isSwiftModule == true {
            return .array
        }
        if identifierNode?.isIdentifier(desired: "Dictionary") == true && typeArguments.children.count == 2 && moduleNode?.isSwiftModule == true {
            return .dictionary
        }
        return .none
    }
}
