import Demangling
import MemberwiseInit

protocol InterfaceNodePrintable: NodePrintable, BoundGenericNodePrintable, TypeNodePrintable, DependentGenericNodePrintable, FunctionTypeNodePrintable {
    mutating func printRoot(_ node: Node) async throws -> Target
}

protocol InterfaceNodePrintableContext: NodePrintableContext, FunctionTypeNodePrintableContext {}

@MemberwiseInit()
struct InterfaceNodePrinterContext: InterfaceNodePrintableContext {
    var isAllocator: Bool = false

    var isBlockOrClosure: Bool = false

    init() {}
}

extension InterfaceNodePrintable {
    mutating func printName(_ name: Node, asPrefixContext: Bool, context: Context?) async -> Node? {
        if printDepth > Self.maxPrintDepth {
            target.write("<<too complex>>")
            return nil
        }
        // Memoize only "default-context" prints. Sub-method prints that depend
        // on caller-side state (asPrefixContext, custom context, an active
        // dependentMemberType chain) can produce different output for the same
        // node and so must not be served from cache. The DAG-explosion case
        // we care about (BoundGeneric typeList children) always recurses
        // through this default path, so the cache still kicks in there.
        let cacheKey = ObjectIdentifier(name)
        let canCache = !asPrefixContext && context == nil && dependentMemberTypeDepth == 0
        if canCache, let cached = printCache[cacheKey] {
            target.append(cached)
            return nil
        }
        printDepth += 1
        defer { printDepth -= 1 }
        if canCache {
            // Redirect output to a fresh sub-target so we can capture exactly
            // the slice produced for `name` and memoize it. The `swap` keeps
            // `self.target` as the live target for nested print calls (which
            // mutate `self`), then we swap back and splice the captured
            // fragment into the original target.
            var subTarget = Target()
            swap(&target, &subTarget)
            let result = await dispatchPrintName(name, context: context)
            swap(&target, &subTarget)
            printCache[cacheKey] = subTarget
            target.append(subTarget)
            return result
        }
        return await dispatchPrintName(name, context: context)
    }

    private mutating func dispatchPrintName(_ name: Node, context: Context?) async -> Node? {
        if await printNameInBase(name, context: context) {
            return nil
        }
        if await printNameInBoundGeneric(name, context: context) {
            return nil
        }
        if await printNameInType(name, context: context) {
            return nil
        }
        if await printNameInDependentGeneric(name, context: context) {
            return nil
        }
        if await printNameInFunction(name, context: context) {
            return nil
        }
        return nil
    }
    
    var needsSkipFirstNodeKinds: Set<Node.Kind> {
        [
            .asyncFunctionPointer,
            .asyncSuspendResumePartialFunction,
            .mergedFunction,
        ]
    }
    
}
