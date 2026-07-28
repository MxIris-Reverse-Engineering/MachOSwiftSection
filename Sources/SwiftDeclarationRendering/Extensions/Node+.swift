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

extension DemanglingNode {
    /// Zero-materialization semantic print. For store-backed nodes the
    /// type-reference identity scopes materialize just the nominal reference
    /// subtrees on demand, via the engine's lazy scope hook.
    ///
    /// This is the only `printSemantic`, deliberately: a concrete `Node`
    /// overload used to sit alongside it and — being the better overload for
    /// every `Node` caller — shadowed this one while running
    /// `NodePrinter<SemanticString>` (itself a thin wrapper over the same
    /// `DemanglingPrinter<Target, Node>` engine) with no stack guard at all.
    /// A deeply nested generic symbol printed through a `Node` could therefore
    /// overflow the stack where the identical `NodeReference` call would not.
    ///
    /// The guard is the engine's own `print(_:options:)` rather than a
    /// `StackSafeExecutor.execute` wrapper around `printRoot`. `execute` has to
    /// assume the worst about every input, so on a 512KB stack — which is what
    /// every Swift Concurrency cooperative worker and every libdispatch worker
    /// gets — it hands *every* call to a large-stack worker and blocks the
    /// caller on a semaphore until that worker returns. `print(_:options:)`
    /// runs the recursion inline against a stack floor and pays for a worker
    /// only for a tree that actually reaches it. Every `printSemantic` call
    /// site sits on a printing hot path, so the difference is one
    /// dispatch-and-block per printed declaration.
    public func printSemantic(using options: DemangleOptions = .default) -> SemanticString {
        DemanglingPrinter<SemanticString, Self>.print(self, options: options)
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
