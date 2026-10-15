import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Internals) import Demangling

/// How a generic context's parameters split into depths — the first half of
/// the `(depth, index)` pair every mangled reference to a parameter carries
/// (`τ_1_0`, printed `A1`).
///
/// A generic context descriptor records its parameters as one cumulative list,
/// outermost first, and records where one depth ends and the next begins
/// nowhere. The parent chain does not say it either, for two reasons:
///
/// - A type that declares no parameter of its own — `Middle` in
///   `Outer<A>.Middle.Inner<B>` — is generic all the same (it inherits `A`),
///   so it has a generic context, yet it opens no depth: `B` is at depth 1.
/// - An extension declares no parameter either, but its context carries every
///   parameter of the type it extends, and those can span several depths:
///   `extension Outer.SecondMiddle where A == Int` covers `Outer`'s depth 0 and
///   `SecondMiddle`'s depth 1 in one context.
///
/// So a depth is opened by each type or opaque-type context that adds
/// parameters, and by each level of an extended type that declares them —
/// what the compiler's generic signatures say, and the levels the runtime's
/// `_buildDemanglingForContext` hangs a nested instantiation's arguments on.
/// Counting every generic ancestor as a depth instead named `Inner`'s `B` as
/// `A2` in printed headers and in `GenericSpecializer`'s requests, while every
/// field and requirement read `A1`.
public struct GenericParameterDepthLayout: Sendable, Hashable {
    /// The number of parameters at each depth, outermost first. Never holds a
    /// zero.
    public let parameterCountsByDepth: [Int]

    public init(parameterCountsByDepth: [Int]) {
        self.parameterCountsByDepth = parameterCountsByDepth.filter { $0 > 0 }
    }

    /// Every parameter of the context — its `numParams`.
    public var parameterCount: Int {
        parameterCountsByDepth.reduce(0, +)
    }

    public var depthCount: Int {
        parameterCountsByDepth.count
    }

    /// The `(depth, index)` of the parameter at `flatIndex` in the cumulative
    /// parameter list, `nil` past its end.
    public func position(ofParameterAt flatIndex: Int) -> (depth: Int, index: Int)? {
        guard flatIndex >= 0 else { return nil }
        var remaining = flatIndex
        for (depth, count) in parameterCountsByDepth.enumerated() {
            if remaining < count { return (depth, remaining) }
            remaining -= count
        }
        return nil
    }

    /// The position in the cumulative parameter list of the parameter
    /// `(depth, index)`, `nil` when there is no such parameter.
    public func flatIndex(depth: Int, index: Int) -> Int? {
        guard parameterCountsByDepth.indices.contains(depth), index >= 0, index < parameterCountsByDepth[depth] else { return nil }
        return parameterCountsByDepth[..<depth].reduce(0, +) + index
    }

    /// `elements`, one per parameter in cumulative order, grouped by depth;
    /// `nil` when the count does not match.
    public func grouped<Element>(_ elements: [Element]) -> [[Element]]? {
        guard elements.count == parameterCount else { return nil }
        var groups: [[Element]] = []
        groups.reserveCapacity(parameterCountsByDepth.count)
        var start = elements.startIndex
        for count in parameterCountsByDepth {
            groups.append(Array(elements[start ..< start + count]))
            start += count
        }
        return groups
    }
}

// MARK: - Reading a descriptor

extension GenericParameterDepthLayout {
    /// The depth layout of `descriptor`'s generic context, `nil` for a
    /// descriptor that is not generic.
    public static func make(for descriptor: ContextDescriptorWrapper, in context: some ReadingContext) throws -> GenericParameterDepthLayout? {
        guard let genericContext = try descriptor.genericContext(in: context) else { return nil }
        return make(for: genericContext, ownedBy: descriptor, in: context)
    }

    /// The depth layout of `genericContext`, read from `descriptor` — for a
    /// caller that holds the context already.
    ///
    /// The parent chain is walked the way `TargetGenericContext` walks it to
    /// collect `parentParameters` — every type or extension ancestor with a
    /// generic context, the first unresolvable parent ending the walk — so the
    /// ancestors line up one to one with those cumulative lists. Should they
    /// not, or an extension's extended type not split the way its parameter
    /// count says, the level counts as one depth: the layout the parent chain
    /// alone gives, never a guess past it.
    public static func make<Header>(
        for genericContext: TargetGenericContext<Header>,
        ownedBy descriptor: ContextDescriptorWrapper,
        in context: some ReadingContext
    ) -> GenericParameterDepthLayout {
        make(for: genericContext, ownedBy: descriptor.contextDescriptor, in: context)
    }

    /// The depth layout of `genericContext`, read from `descriptor` — the
    /// form for a caller holding the descriptor itself rather than a wrapper.
    public static func make<Header>(
        for genericContext: TargetGenericContext<Header>,
        ownedBy descriptor: some ContextDescriptorProtocol,
        in context: some ReadingContext
    ) -> GenericParameterDepthLayout {
        let ancestors = genericAncestorsOutermostFirst(of: descriptor, in: context)
        let ancestorExtensions: [ExtensionContextDescriptor?] = ancestors.count == genericContext.parentParameters.count
            ? ancestors.map(\.extensionContextDescriptor)
            : Array(repeating: nil, count: genericContext.parentParameters.count)
        let levelExtensions = ancestorExtensions + [descriptor as? ExtensionContextDescriptor]
        let cumulativeCounts = genericContext.parentParameters.map(\.count) + [genericContext.parameters.count]

        var parameterCountsByDepth: [Int] = []
        var previousCumulativeCount = 0
        for (levelExtension, cumulativeCount) in zip(levelExtensions, cumulativeCounts) {
            let addedCount = cumulativeCount - previousCumulativeCount
            previousCumulativeCount = max(previousCumulativeCount, cumulativeCount)
            guard addedCount > 0 else { continue }
            if let levelExtension,
               let extendedLevelCounts = extendedTypeParameterCountsByLevel(of: levelExtension, in: context),
               extendedLevelCounts.reduce(0, +) == addedCount {
                parameterCountsByDepth.append(contentsOf: extendedLevelCounts)
            } else {
                parameterCountsByDepth.append(addedCount)
            }
        }
        return GenericParameterDepthLayout(parameterCountsByDepth: parameterCountsByDepth)
    }

    /// The ancestors of `descriptor` whose generic contexts the descriptor's
    /// own `parentParameters` record, outermost first.
    private static func genericAncestorsOutermostFirst(of descriptor: some ContextDescriptorProtocol, in context: some ReadingContext) -> [ContextDescriptorWrapper] {
        var ancestorsInnermostFirst: [ContextDescriptorWrapper] = []
        var parent = (try? descriptor.parent(in: context))?.flatMap(\.resolved)
        while let currentParent = parent {
            switch currentParent {
            case .type, .extension:
                if currentParent.contextDescriptor.layout.flags.isGeneric {
                    ancestorsInnermostFirst.append(currentParent)
                }
            default:
                break
            }
            parent = (try? currentParent.parent(in: context))?.flatMap(\.resolved)
        }
        return ancestorsInnermostFirst.reversed()
    }

    /// How many parameters each level of an extension's extended type
    /// declares, outermost first: the argument lists of its extended-context
    /// mangling, which IRGen spells as the self type in the extension's own
    /// parameters (`Outer<A>.SecondMiddle<C>`).
    private static func extendedTypeParameterCountsByLevel(of extensionDescriptor: ExtensionContextDescriptor, in context: some ReadingContext) -> [Int]? {
        guard let extendedContext = try? extensionDescriptor.extendedContext(in: context),
              let extendedTypeNode = try? SymbolicDemangler.demangleType(for: extendedContext, in: context)
        else { return nil }
        let argumentLists = GenericArgumentBinding.argumentListsByLevel(ofInstantiatedTypeNode: extendedTypeNode)
        guard !argumentLists.isEmpty else { return nil }
        return argumentLists.map(\.count)
    }
}
