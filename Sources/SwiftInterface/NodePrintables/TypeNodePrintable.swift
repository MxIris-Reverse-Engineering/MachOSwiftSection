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
}
