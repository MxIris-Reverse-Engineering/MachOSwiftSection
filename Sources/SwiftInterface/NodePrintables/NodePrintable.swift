import Demangling
import Foundation
import Utilities

protocol NodePrintableContext {}

protocol NodePrintable {
    associatedtype Target: NodePrinterTarget

    associatedtype Context: NodePrintableContext

    var target: Target { set get }

    var delegate: NodePrintableDelegate? { get }

    var targetNode: Node? { get }

    var dependentMemberTypeDepth: Int { get set }

    @discardableResult
    mutating func printName(_ name: Node, asPrefixContext: Bool, context: Context?) async -> Node?
}

extension NodePrintable {
    mutating func printNameInBase(_ name: Node, context: Context?) async -> Bool {
        switch name.kind {
        case .global:
            await printChildren(name)
        case .module:
            await printModule(name)
        case .identifier:
            await printIdentifier(name)
        case .privateDeclName:
            await printPrivateDeclName(name)
        case .inOut:
            await printFirstChild(name, prefix: "inout ", prefixContext: .context(for: name, state: .printKeyword))
        case .owned:
            await printFirstChild(name, prefix: "__owned ", prefixContext: .context(for: name, state: .printKeyword))
        case .isolated:
            await printFirstChild(name, prefix: "isolated ", prefixContext: .context(for: name, state: .printKeyword))
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
        if dependentMemberTypeDepth > 0 {
            return false
        }
        if context.kind == .module, let text = context.text, !text.isEmpty {
            return true
        }
        return true
    }

    mutating func printModule(_ node: Node, siblingIdentifier: String? = nil) async {
        var moduleName = node.text ?? ""
        if moduleName == objcModule || moduleName == cModule,
           let identifier = siblingIdentifier,
           let delegate,
           let updatedModuleName = await or(await delegate.moduleName(forTypeName: identifier), await delegate.moduleName(forTypeName: identifier.strippedRefSuffix)) {
            moduleName = updatedModuleName
        }
        target.write(moduleName, context: .context(for: node, state: .printModule))
    }

    mutating func printIdentifier(_ node: Node, parentKind: Node.Kind? = nil) async {
        target.write(node.text ?? "", context: .context(for: node, parentKind: parentKind, state: .printIdentifier))
    }

    mutating func printPrivateDeclName(_ node: Node, parentKind: Node.Kind? = nil) async {
        guard let child = node.children.at(1) else { return }
        await printIdentifier(child, parentKind: parentKind)
    }

    @discardableResult
    mutating func printName(_ name: Node) async -> Node? {
        await printName(name, asPrefixContext: false, context: nil)
    }

    @discardableResult
    mutating func printName(_ name: Node, asPrefixContext: Bool) async -> Node? {
        await printName(name, asPrefixContext: asPrefixContext, context: nil)
    }

    @discardableResult
    mutating func printName(_ name: Node, context: Context?) async -> Node? {
        await printName(name, asPrefixContext: false, context: context)
    }

    @discardableResult
    mutating func printOptional(_ optional: Node?, prefix: String? = nil, prefixContext: NodePrintContext? = nil, suffix: String? = nil, suffixContext: NodePrintContext? = nil, asPrefixContext: Bool = false) async -> Node? {
        guard let o = optional else { return nil }
        prefix.map { target.write($0, context: prefixContext) }
        let r = await printName(o, asPrefixContext: asPrefixContext)
        suffix.map { target.write($0, context: suffixContext) }
        return r
    }

    mutating func printFirstChild(_ ofName: Node, prefix: String? = nil, prefixContext: NodePrintContext? = nil, suffix: String? = nil, suffixContext: NodePrintContext? = nil, asPrefixContext: Bool = false) async {
        _ = await printOptional(ofName.children.at(0), prefix: prefix, prefixContext: prefixContext, suffix: suffix, suffixContext: suffixContext, asPrefixContext: asPrefixContext)
    }

    mutating func printSequence<S>(_ names: S, prefix: String? = nil, prefixContext: NodePrintContext? = nil, suffix: String? = nil, suffixContext: NodePrintContext? = nil, separator: String? = nil) async where S: Sequence, S.Element == Node {
        var isFirst = true
        prefix.map { target.write($0, context: prefixContext) }
        for c in names {
            if let s = separator, !isFirst {
                target.write(s)
            } else {
                isFirst = false
            }
            _ = await printName(c)
        }
        suffix.map { target.write($0, context: suffixContext) }
    }

    mutating func printChildren(_ ofName: Node, prefix: String? = nil, prefixContext: NodePrintContext? = nil, suffix: String? = nil, suffixContext: NodePrintContext? = nil, separator: String? = nil) async {
        await printSequence(ofName.children, prefix: prefix, prefixContext: prefixContext, suffix: suffix, suffixContext: suffixContext, separator: separator)
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
