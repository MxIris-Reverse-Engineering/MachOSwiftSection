import SwiftDeclaration
import Demangling

/// The whole-traversal state of an interface printer: every layer's slice,
/// plus the memoization `printName(_:options:)` itself keeps.
protocol InterfaceNodePrintableContext: TypeNodePrintableContext, DependentGenericNodePrintableContext, FunctionTypeNodePrintableContext {
    associatedtype Target: NodePrinterTarget

    /// Mirrors the ``Swift::Demangle::NodePrinter`` recursion guard at
    /// ``swift/lib/Demangling/NodePrinter.cpp:1416``. Each entry into
    /// ``InterfaceNodePrintable/printName(_:options:)`` increments the counter
    /// and the wrapper bails with ``<<too complex>>`` once it would exceed
    /// ``NodePrintable/maxPrintDepth``. Without this, demangle results that
    /// share substitution nodes (a DAG) blow up into ``19^k``-shaped
    /// traversals during printing.
    var printDepth: Int { get set }

    /// Memoization for shared substitution nodes. The demangler returns the
    /// same ``Node`` instance for every back-reference (e.g. ``A23_``), so a
    /// single ``Type<...>`` mangling can produce a DAG that, naively walked
    /// child-by-child, expands into hundreds of thousands of node visits. By
    /// caching the rendered ``Target`` slice keyed by
    /// ``ObjectIdentifier(node)``, every shared node prints once and reuses
    /// the cached fragment thereafter — bringing print cost back to the size
    /// of the unique node set instead of the exponential expansion. The
    /// cache is per printer instance, so it lives only for the duration of one
    /// ``InterfaceNodePrintable/printRoot(_:)`` invocation.
    var printCache: [ObjectIdentifier: Target] { get set }
}

protocol InterfaceNodePrintable: NodePrintable, BoundGenericNodePrintable, TypeNodePrintable, DependentGenericNodePrintable, FunctionTypeNodePrintable where Context: InterfaceNodePrintableContext, Context.Target == Target {
    mutating func printRoot(_ node: Node) async throws -> Target
}

/// The one concrete context. Every role protocol is satisfied by one stored
/// property per name; a name two roles both declare
/// (`knownPackParameterNames`) is one property both read and write. Which
/// layer may *write* a property is what the role protocols say — the type
/// layer reads `isProtocol`, only the declaration layer sets it.
struct InterfaceNodePrinterContext<Target: NodePrinterTarget>: InterfaceNodePrintableContext, MemberDeclarationNodePrintableContext {
    var dependentMemberTypeDepth = 0

    /// How many `repeat` patterns enclose the node being printed. `each` is
    /// only ever written inside one.
    var packExpansionDepth = 0

    /// Generic parameters known to be packs, by printed name.
    ///
    /// A parameter reference carries no pack marker — a use site is identical
    /// to an ordinary parameter — so `repeat each A` demangles to a plain
    /// reference and prints as `repeat A`, which does not compile. Two sources
    /// fill this in, and they are complementary:
    ///
    /// - the enclosing signature, recorded by
    ///   ``DependentGenericNodePrintable/printGenericSignature(_:enclosingGenericType:)``
    ///   as it decides which parameters print as `each A`. Available whenever
    ///   the signature and the type share a printer, i.e. for functions — which
    ///   is the only place several packs can occur.
    /// - the expansion's own count type, recorded by
    ///   ``FunctionTypeNodePrintable/printPackExpansion(_:)``. This is what
    ///   covers a type's field, whose type tree carries no signature — and it
    ///   suffices there, because a generic type may declare at most one pack
    ///   ("generic type cannot declare more than one type pack").
    var knownPackParameterNames: Set<String> = []

    var printDepth = 0

    var printCache: [ObjectIdentifier: Target] = [:]

    /// The declaration being printed belongs to a protocol or a protocol
    /// extension, so its first generic parameter `A` is spelled `Self`.
    var isProtocol = false

    /// The declaration whose opaque return types the delegate resolves; nil
    /// while a bare type is being printed.
    var targetNode: Node?
}

extension InterfaceNodePrintable {
    mutating func printName(_ name: Node, options: NodePrintOptions) async {
        if context.printDepth > Self.maxPrintDepth {
            target.write("<<too complex>>")
            return
        }
        // Memoize only "default-context" prints. Sub-method prints that depend
        // on caller-side state (non-default options, an active
        // dependentMemberType chain) can produce different output for the same
        // node and so must not be served from cache. The DAG-explosion case
        // we care about (BoundGeneric typeList children) always recurses
        // through this default path, so the cache still kicks in there.
        let cacheKey = ObjectIdentifier(name)
        // `packExpansionDepth` joins the list for the same reason
        // `dependentMemberTypeDepth` is on it: inside a `repeat` pattern a
        // parameter renders as `(each A)` and outside it as `A`, so caching
        // one rendering under the node's identity would serve it to the other.
        let canCache = options == .default && context.dependentMemberTypeDepth == 0 && context.packExpansionDepth == 0
        if canCache, let cached = context.printCache[cacheKey] {
            target.append(cached)
            return
        }
        context.printDepth += 1
        defer { context.printDepth -= 1 }
        if canCache {
            // Redirect output to a fresh sub-target so we can capture exactly
            // the slice produced for `name` and memoize it. The `swap` keeps
            // `self.target` as the live target for nested print calls (which
            // mutate `self`), then we swap back and splice the captured
            // fragment into the original target.
            var subTarget = Target()
            swap(&target, &subTarget)
            await dispatchPrintName(name, options: options)
            swap(&target, &subTarget)
            context.printCache[cacheKey] = subTarget
            target.append(subTarget)
            return
        }
        await dispatchPrintName(name, options: options)
    }

    private mutating func dispatchPrintName(_ name: Node, options: NodePrintOptions) async {
        if await printNameInBase(name) {
            return
        }
        if await printNameInBoundGeneric(name) {
            return
        }
        if await printNameInType(name) {
            return
        }
        if await printNameInDependentGeneric(name) {
            return
        }
        if await printNameInFunction(name, options: options) {
            return
        }
    }
}
