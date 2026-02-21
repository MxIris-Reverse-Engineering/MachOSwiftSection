import Demangling

protocol TypeNodePrintable: NodePrintable {
    mutating func printNameInType(_ name: Node, context: Context?) async -> Bool
    mutating func printType(_ name: Node) async
}

extension TypeNodePrintable {
    mutating func printNameInType(_ name: Node, context: Context?) async -> Bool {
        switch name.kind {
        case .type,
             .weak:
            await printFirstChild(name)
        case .enum,
             .structure,
             .class,
             .protocol,
             .typeAlias:
            await printType(name)
        case .tuple:
            await printTuple(name)
        case .protocolList:
            await printProtocolList(name)
        case .protocolListWithClass:
            await printProtocolListWithClass(name)
        case .protocolListWithAnyObject:
            await printProtocolListWithAnyObject(name)
        case .typeList:
            await printTypeList(name)
        case .metatype:
            await printMetatype(name)
        case .existentialMetatype:
            await printExistentialMetatype(name)
        case .opaqueReturnType:
            await printOpaqueReturnType(name)
        case .opaqueReturnTypeOf:
            await printChildren(name)
        case .opaqueType:
            await printOpaqueType(name)
        case .symbolicExtendedExistentialType:
            await printSymbolicExtendedExistentialType(name)
        default:
            return false
        }
        return true
    }

    mutating func printOpaqueReturnType(_ node: Node) async {
        target.write("some", context: .context(for: node, state: .printKeyword))
        if let targetNode, let opaqueType = await delegate?.opaqueType(forNode: targetNode, index: node.first(of: .opaqueReturnTypeIndex)?.index?.int) {
            target.writeSpace()
            target.write(opaqueType)
        }
    }

    mutating func printOpaqueType(_ name: Node) async {
//        printFirstChild(name)
        await printOptional(name[safeChild: 2])
    }

    mutating func printType(_ name: Node) async {
        if name.kind == .type, let firstChild = name.children.first {
            await printType(firstChild)
            return
        }
        guard let context = name.children.first else { return }

        if shouldPrintContext(context) {
            let currentPos = target.count
            if context.kind == .module {
                let siblingIdentifier = name.children.at(1)?.text
                await printModule(context, siblingIdentifier: siblingIdentifier)
            } else {
                _ = await printName(context, asPrefixContext: true)
            }
            if target.count != currentPos {
                target.write(".")
            }
        }

        if let one = name.children.at(1) {
            if one.kind != .privateDeclName {
                if one.kind == .identifier {
                    await printIdentifier(one, parentKind: name.kind)
                } else {
                    _ = await printName(one)
                }
            }
            if let pdn = name.children.first(where: { $0.kind == .privateDeclName }) {
                await printPrivateDeclName(pdn, parentKind: name.kind)
            }
        }
    }

    mutating func printTypeList(_ name: Node) async {
        await printChildren(name)
    }

    mutating func printProtocolList(_ name: Node) async {
        guard let typeList = name.children.first else { return }
        if typeList.children.isEmpty {
            target.write("Any", context: .context(for: name, state: .printKeyword))
        } else {
            await printChildren(typeList, separator: " & ")
        }
    }

    mutating func printProtocolListWithClass(_ name: Node) async {
        guard name.children.count >= 2 else { return }
        _ = await printOptional(name.children.at(1), suffix: " & ")
        if let protocolsTypeList = name.children.first?.children.first {
            await printChildren(protocolsTypeList, separator: " & ")
        }
    }

    mutating func printProtocolListWithAnyObject(_ name: Node) async {
        guard let prot = name.children.first, let protocolsTypeList = prot.children.first else { return }
        if protocolsTypeList.children.count > 0 {
            await printChildren(protocolsTypeList, suffix: " & ", separator: " & ")
        }
        target.write("Swift", context: .context(for: name, state: .printModule))
        target.write(".")
        target.write("AnyObject", context: .context(for: name, parentKind: .protocol, state: .printIdentifier))
    }

    mutating func printTuple(_ name: Node) async {
        await printChildren(name, prefix: "(", suffix: ")", separator: ", ")
    }

    mutating func printMetatype(_ name: Node) async {
        if name.children.count == 2 {
            await printFirstChild(name, suffix: " ")
        }
        guard let type = name.children.at(name.children.count == 2 ? 1 : 0)?.children.first else { return }
        let needParens = !type.isSimpleType
        target.write(needParens ? "(" : "")
        _ = await printName(type)
        target.write(needParens ? ")" : "")
        target.write(".")
        target.write(type.kind.isExistentialType ? "Protocol" : "Type", context: .context(for: name, state: .printKeyword))
    }

    mutating func printExistentialMetatype(_ name: Node) async {
        if name.children.count == 2 {
            await printFirstChild(name, suffix: " ")
        }
        _ = await printOptional(name.children.at(name.children.count == 2 ? 1 : 0), suffix: ".Type")
    }

    mutating func printSymbolicExtendedExistentialType(_ name: Node) async {
        guard let second = name.children.at(1) else { return }
        _ = await printName(second)
        if let third = name.children.at(2) {
            target.write(", ")
            _ = await printName(third)
        }
    }
}
