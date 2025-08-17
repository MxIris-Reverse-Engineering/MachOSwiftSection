import Demangle
import Foundation

protocol NodePrintable {
    associatedtype Target: NodePrinterTarget

    var target: Target { set get }

    @discardableResult
    mutating func printName(_ name: Node, asPrefixContext: Bool) -> Node?
}

extension NodePrintable {
    mutating func printNameInBase(_ name: Node) -> Bool {
        switch name.kind {
        case .module:
            target.write(name.text ?? "", context: .context(for: name, state: .printModule))
        case .identifier:
            printIdentifier(name)
        case .privateDeclName:
            printPrivateDeclName(name)
        case .inOut:
            printFirstChild(name, prefix: "inout ")
        case .owned:
            printFirstChild(name, prefix: "__owned ")
        case .isolated: printFirstChild(name, prefix: "isolated ")
        case .isolatedAnyFunctionType: target.write("@isolated(any) ")
        default:
            return false
        }
        return true
    }

    func shouldPrintContext(_ context: Node) -> Bool {
        if let dependentMemberType = context.parent?.parent?.parent?.parent, dependentMemberType.kind == .dependentMemberType {
            return false
        }
        if context.kind == .module, let text = context.text, !text.isEmpty {
            return true
        }
        return true
    }

    @discardableResult
    mutating func printName(_ name: Node) -> Node? {
        printName(name, asPrefixContext: false)
    }

    @discardableResult
    mutating func printOptional(_ optional: Node?, prefix: String? = nil, suffix: String? = nil, asPrefixContext: Bool = false) -> Node? {
        guard let o = optional else { return nil }
        prefix.map { target.write($0) }
        let r = printName(o)
        suffix.map { target.write($0) }
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
    
    mutating func printIdentifier(_ node: Node) {
        target.write(node.text ?? "", context: .context(for: node, state: .printIdentifier))
    }
    
    mutating func printPrivateDeclName(_ node: Node) {
        target.write(node.children.at(1)?.text ?? "", context: .context(for: node, state: .printIdentifier))
    }
}
