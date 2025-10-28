import Demangling
import Foundation

protocol NodePrintableContext {}

protocol NodePrintable {
    associatedtype Target: NodePrinterTarget
    
    associatedtype Context: NodePrintableContext
    
    var target: Target { set get }
    
    var delegate: NodePrintableDelegate? { get }
    
    var targetNode: Node? { get }
    
    @discardableResult
    mutating func printName(_ name: Node, asPrefixContext: Bool, context: Context?) -> Node?
}

extension NodePrintable {
    mutating func printNameInBase(_ name: Node, context: Context?) -> Bool {
        switch name.kind {
        case .global:
            printChildren(name)
        case .module:
            printModule(name)
        case .identifier:
            printIdentifier(name)
        case .privateDeclName:
            printPrivateDeclName(name)
        case .inOut:
            printFirstChild(name, prefix: "inout ", prefixContext: .context(for: name, state: .printKeyword))
        case .owned:
            printFirstChild(name, prefix: "__owned ", prefixContext: .context(for: name, state: .printKeyword))
        case .isolated:
            printFirstChild(name, prefix: "isolated ", prefixContext: .context(for: name, state: .printKeyword))
        case .isolatedAnyFunctionType:
            target.write("@isolated(any) ", context: .context(for: name, state: .printKeyword))
        case .dynamicSelf:
            target.write("Self", context: .context(for: name, state: .printKeyword))
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

    mutating func printModule(_ node: Node) {
        var moduleName = node.text ?? ""
        if moduleName == objcModule || moduleName == cModule, let identifier = node.parent?.children.at(1)?.text, let updatedModuleName = delegate?.moduleName(forTypeName: identifier) ?? delegate?.moduleName(forTypeName: identifier.strippedRefSuffix) {
            moduleName = updatedModuleName
        }
        target.write(moduleName, context: .context(for: node, state: .printModule))
    }

    mutating func printIdentifier(_ node: Node) {
        target.write(node.text ?? "", context: .context(for: node, state: .printIdentifier))
    }

    mutating func printPrivateDeclName(_ node: Node) {
        guard let child = node.children.at(1) else { return }
        printIdentifier(child)
    }

    @discardableResult
    mutating func printName(_ name: Node) -> Node? {
        printName(name, asPrefixContext: false, context: nil)
    }

    @discardableResult
    mutating func printName(_ name: Node, asPrefixContext: Bool) -> Node? {
        printName(name, asPrefixContext: asPrefixContext, context: nil)
    }
    
    @discardableResult
    mutating func printName(_ name: Node, context: Context?) -> Node? {
        printName(name, asPrefixContext: false, context: context)
    }

    @discardableResult
    mutating func printOptional(_ optional: Node?, prefix: String? = nil, prefixContext: NodePrintContext? = nil, suffix: String? = nil, suffixContext: NodePrintContext? = nil, asPrefixContext: Bool = false) -> Node? {
        guard let o = optional else { return nil }
        prefix.map { target.write($0, context: prefixContext) }
        let r = printName(o, asPrefixContext: asPrefixContext)
        suffix.map { target.write($0, context: suffixContext) }
        return r
    }

    mutating func printFirstChild(_ ofName: Node, prefix: String? = nil, prefixContext: NodePrintContext? = nil, suffix: String? = nil, suffixContext: NodePrintContext? = nil, asPrefixContext: Bool = false) {
        _ = printOptional(ofName.children.at(0), prefix: prefix, prefixContext: prefixContext, suffix: suffix, suffixContext: suffixContext, asPrefixContext: asPrefixContext)
    }

    mutating func printSequence<S>(_ names: S, prefix: String? = nil, prefixContext: NodePrintContext? = nil, suffix: String? = nil, suffixContext: NodePrintContext? = nil, separator: String? = nil) where S: Sequence, S.Element == Node {
        var isFirst = true
        prefix.map { target.write($0, context: prefixContext) }
        for c in names {
            if let s = separator, !isFirst {
                target.write(s)
            } else {
                isFirst = false
            }
            _ = printName(c)
        }
        suffix.map { target.write($0, context: suffixContext) }
    }

    mutating func printChildren(_ ofName: Node, prefix: String? = nil, prefixContext: NodePrintContext? = nil, suffix: String? = nil, suffixContext: NodePrintContext? = nil, separator: String? = nil) {
        printSequence(ofName.children, prefix: prefix, prefixContext: prefixContext, suffix: suffix, suffixContext: suffixContext, separator: separator)
    }
}

extension String {
    fileprivate var strippedRefSuffix: String {
        if hasSuffix("Ref") {
            return String(dropLast(3))
        }
        return self
    }
}
