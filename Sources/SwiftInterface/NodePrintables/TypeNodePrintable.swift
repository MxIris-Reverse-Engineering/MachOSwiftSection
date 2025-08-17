import Demangle

protocol TypeNodePrintable: NodePrintable {
    mutating func printNameInType(_ name: Node) -> Bool
    mutating func printType(_ name: Node)
}

extension TypeNodePrintable {
    mutating func printNameInType(_ name: Node) -> Bool {
        switch name.kind {
        case .type:
            printFirstChild(name)
        case .enum,
             .structure,
             .class,
             .protocol,
             .typeAlias:
            printType(name)
        case .tuple:
            printTuple(name)
        case .protocolList:
            printProtocolList(name)
        case .protocolListWithClass:
            printProtocolListWithClass(name)
        case .protocolListWithAnyObject:
            printProtocolListWithAnyObject(name)
        case .typeList:
            printTypeList(name)
        case .metatype:
            printMetatype(name)
        case .existentialMetatype:
            printExistentialMetatype(name)
        default:
            return false
        }
        return true
    }

    mutating func printType(_ name: Node) {
        if name.kind == .type, let firstChild = name.children.first {
            printType(firstChild)
            return
        }
        guard let context = name.children.first else { return }

        if shouldPrintContext(context) {
            let currentPos = target.count
            _ = printName(context, asPrefixContext: true)
            if target.count != currentPos {
                target.write(".")
            }
        }

        if let one = name.children.at(1) {
            if one.kind != .privateDeclName {
                _ = printName(one)
            }
            if let pdn = name.children.first(where: { $0.kind == .privateDeclName }) {
                _ = printName(pdn)
            }
        }
    }

    mutating func printTypeList(_ name: Node) {
        printChildren(name)
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
        target.write("Swift.AnyObject")
    }

    mutating func printTuple(_ name: Node) {
        printChildren(name, prefix: "(", suffix: ")", separator: ", ")
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
}
