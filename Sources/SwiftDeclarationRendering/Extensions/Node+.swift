import Foundation
@_spi(Internals) import Demangling
import Semantic

extension SemanticString: @retroactive NodePrinterTarget {
    public mutating func pushTypeReferenceScope(_ node: @autoclosure () -> Node?) {
        // A failed remangle degrades to a nil (barrier) scope: the span's
        // tokens carry no identity rather than inheriting the enclosing
        // type's, which would mislabel them.
        pushIdentifierScope(node().flatMap { try? mangleAsString($0) })
    }

    public mutating func popTypeReferenceScope() {
        popIdentifierScope()
    }

    public mutating func write(_ content: String, context: NodePrintContext?) {
        guard let context else {
            write(content)
            return
        }
        switch context.state {
        case .printFunctionParameters:
            write(content, type: .function(.declaration))
        case .printIdentifier:
            let semanticType: SemanticType
            switch context.parentKind {
            case .function:
                semanticType = .function(.declaration)
            case .variable:
                semanticType = .variable
            case .enum:
                semanticType = .type(.enum, .name)
            case .structure:
                semanticType = .type(.struct, .name)
            case .class:
                semanticType = .type(.class, .name)
            case .protocol:
                semanticType = .type(.protocol, .name)
            default:
                semanticType = .standard
            }
            write(content, type: semanticType)
        case .printModule:
            write(content, type: .other)
        case .printKeyword:
            write(content, type: .keyword)
        case .printType:
            write(content, type: .type(.other, .name))
        }
    }
}

extension Node {
    public func printSemantic(using options: DemangleOptions = .default) -> SemanticString {
        var printer = NodePrinter<SemanticString>(options: options)
        return printer.printRoot(self)
    }
}

extension DemanglingNode {
    /// Zero-materialization semantic print through the same generic engine
    /// as `Node.printSemantic` — for store-backed nodes the type-reference
    /// identity scopes materialize just the nominal reference subtrees on
    /// demand, via the engine's lazy scope hook.
    public func printSemantic(using options: DemangleOptions = .default) -> SemanticString {
        StackSafeExecutor.execute {
            var printer = DemanglingPrinter<SemanticString, Self>(options: options)
            return printer.printRoot(self)
        }
    }
}

extension Node {
    package var hasWeakNode: Bool {
        preorder().first { $0.kind == .weak } != nil
    }

    package var hasUnownedNode: Bool {
        preorder().first { $0.kind == .unowned } != nil
    }

    package var hasUnmanagedNode: Bool {
        preorder().first { $0.kind == .unmanaged } != nil
    }
}
