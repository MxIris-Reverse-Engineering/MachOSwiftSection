import Foundation
@_spi(Internals) import Demangling
import Semantic

extension SemanticString: @retroactive NodePrinterTarget {
    /// The atom count, which is what the printer's delta probe needs: a
    /// non-empty `write` appends exactly one atom (empty-stringed components
    /// are dropped when atoms are built), so the value changes whenever
    /// something was actually emitted.
    ///
    /// Deliberately not the rendered text's length — the requirement exists
    /// because `String.count` fails that contract: appending a combining mark
    /// merges into the preceding grapheme cluster and leaves the count
    /// unchanged, silently dropping a qualified-name separator.
    public var writtenUnitCount: Int { count }

    public mutating func pushTypeReferenceScope(_ node: @autoclosure () -> Node?) {
        // A failed remangle degrades to a nil (barrier) scope: the span's
        // tokens carry no identity rather than inheriting the enclosing
        // type's, which would mislabel them.
        pushIdentifierScope(node().flatMap { try? mangleAsString($0) })
    }

    public mutating func popTypeReferenceScope() {
        popIdentifierScope()
    }

    public mutating func write(_ content: String, context: @autoclosure () -> NodePrintContext?) {
        guard let context = context() else {
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
    /// The guard is the engine's own `print(_:options:)`, which routes through
    /// `StackSafeExecutor.execute` — probe the calling thread's remaining
    /// stack against a 2MB floor, run inline when it passes, hop to an 8MB
    /// pool worker and block on a semaphore when it does not. An earlier
    /// version of this comment claimed the engine's entry point "runs the
    /// recursion inline and pays for a worker only for a tree that actually
    /// reaches it"; it does not. Darwin gives every thread but the main one a
    /// 512KB stack, so on a cooperative or libdispatch worker the probe never
    /// passes and *every* call hops.
    ///
    /// That cost is upstream's deliberate trade (`swift-demangling` 7b86137):
    /// before it, the printer recursed unguarded and a deeply nested generic
    /// really did overflow a 512KB worker. It is paid down at a *batch*
    /// boundary, never here — a `withLargeStack` around this single call would
    /// save exactly the one hop it adds. `SymbolIndexStore.buildStorageImpl`
    /// does that for the synchronous sweep, because it owns a loop; the
    /// printer's loop lives in `SwiftDeclarationPrinter` and is `async`, which
    /// a synchronous wrapper cannot enclose. The async side's batch boundary
    /// is the TASK instead (evolution proposal
    /// `large-stack-executor-and-cross-version-parallelism`): the library's
    /// async entry points run on the demangler's 16MB `LargeStackTaskExecutor`
    /// through `LargeStackTaskExecution.run`, where the probe passes at every
    /// entry and this call runs inline. The hop is what happens OFF that path
    /// — a host that disabled the executor, or a runtime without task
    /// executors (below macOS 15).
    ///
    /// **Do not "modernize" this onto `runPrintWalk(using:)`.** Upstream added
    /// that protocol requirement as the dispatch hook behind
    /// `print(using:) -> String`, for the single purpose of letting a
    /// `NodeReference`'s arena walk be selected in generic and existential
    /// contexts. It returns `String` because that is what it dispatches for —
    /// a custom `Target` is out of its remit by design, not by oversight, so it
    /// is not "the newer way to print" and there is nothing here to migrate to
    /// it. For a non-`String` target the engine's static
    /// `DemanglingPrinter<Target, SomeNode>.print(_:options:)` is the only
    /// entry point, and will remain so. It is byte-for-byte unchanged across
    /// the `runPrintWalk` introduction — including the `StackSafeExecutor`
    /// wrapper this comment exists to explain (verified upstream on a
    /// deliberately 512KB-stacked thread against 600 levels of nested
    /// generics, which survives only because of that hop).
    ///
    /// Worth noting *why* the shadowing hazard above is a recurring shape
    /// rather than a one-off: upstream hit the mirror image of it in the same
    /// period — a concrete method silently shadowing a protocol-extension
    /// member, where this one was a concrete overload silently shadowing the
    /// stack-guarded generic. Swift's "more specific wins" static dispatch
    /// swaps the implementation in both directions with no diagnostic.
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
