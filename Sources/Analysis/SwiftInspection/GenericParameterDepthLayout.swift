import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Internals) import MachOSymbols
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
    ///
    /// Right for a type, whose anonymous ancestors never add parameters (Swift
    /// declares no type in a generic function). An opaque type descriptor's
    /// do — a generic function's context, a debug build's property's — so
    /// its layout comes from `make(forOpaqueType:genericContext:in:)`.
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

// MARK: - Reading an opaque type descriptor

extension GenericParameterDepthLayout {
    /// The depth layout of an opaque type descriptor's generic context: the
    /// depths of the declaration the opaque result belongs to, then one for
    /// the opaque parameters themselves. `nil` when the depths cannot be told.
    ///
    /// An opaque type's parent chain holds what a type's does not: anonymous
    /// contexts that add parameters. A generic function's or subscript's adds
    /// the declaration's own, one depth, and sits in the type or extension
    /// the declaration belongs to. A property's — the parent IRGen gives the
    /// opaque type under `-enable-anonymous-context-mangled-names`, which the
    /// driver adds to every `-g` build that is not optimized, every Debug
    /// build (`OpaqueTypeDescriptorBuilder::getParent`) — carries the generic
    /// signature of the property's type or extension, yet sits in that type's
    /// PARENT (`AnonymousContextDescriptorBuilder::getParent` asks for the
    /// parent of the property's declaration context), so the type itself is
    /// nowhere on the chain. Passing anonymous contexts over, as
    /// `make(for:ownedBy:in:)` does for a type, read
    /// `KeychainStorage<Value>.publisher` as declared at the top level and its
    /// opaque parameter `τ_1_0` as one at depth 0. So every ancestor that adds
    /// parameters opens a depth here, an anonymous one included, as the
    /// runtime counts them for an opaque type (`_gatherGenericParameterCounts`),
    /// and an extension opens one per level of its extended type that
    /// declares parameters, as everywhere in this type.
    ///
    /// A property declared in an extension is the one context that adds
    /// several depths at once: an extension sits in the module, so the
    /// property's context adds every parameter of the extended type —
    /// `extension Outer.Inner { var values: some Sequence<B> }` adds `Outer`'s
    /// `A` and `Inner`'s `B` together. Its mangled name, which every such
    /// context carries, names the extended type, and that type's descriptor,
    /// found by its `…Mn` symbol, splits them. Without the descriptor — a
    /// stripped image's internal type, or, read from a file, a type another
    /// image declares — the answer is `nil`: one depth too few would read one
    /// of the type's parameters as the opaque one.
    package static func make<Header>(
        forOpaqueType descriptor: OpaqueTypeDescriptor,
        genericContext: TargetGenericContext<Header>,
        in context: some ReadingContext
    ) -> GenericParameterDepthLayout? {
        guard let ancestors = ancestorsInnermostFirst(of: descriptor, in: context) else { return nil }
        var parameterCountsByDepth: [Int] = []
        var cumulativeCount = 0
        for (position, ancestor) in ancestors.enumerated().reversed() {
            guard ancestor.contextDescriptor.layout.flags.isGeneric else { continue }
            guard let ancestorGenericContext = try? ancestor.genericContext(in: context) else { return nil }
            let ancestorCount = ancestorGenericContext.parameters.count
            guard ancestorCount > cumulativeCount else { continue }
            let addedCount = ancestorCount - cumulativeCount
            switch ancestor {
            case .extension(let extensionDescriptor):
                if let extendedLevelCounts = extendedTypeParameterCountsByLevel(of: extensionDescriptor, in: context),
                   extendedLevelCounts.reduce(0, +) == addedCount {
                    parameterCountsByDepth.append(contentsOf: extendedLevelCounts)
                } else {
                    parameterCountsByDepth.append(addedCount)
                }
            case .anonymous(let anonymousDescriptor):
                let sitsInModule = ancestors.indices.contains(position + 1) && ancestors[position + 1].isModule
                guard let levelCounts = parameterCountsByLevel(addedBy: anonymousDescriptor, addedCount: addedCount, sitsInModule: sitsInModule, in: context) else {
                    return nil
                }
                parameterCountsByDepth.append(contentsOf: levelCounts)
            default:
                parameterCountsByDepth.append(addedCount)
            }
            cumulativeCount = ancestorCount
        }
        let opaqueParameterCount = genericContext.parameters.count - cumulativeCount
        guard opaqueParameterCount > 0 else { return nil }
        parameterCountsByDepth.append(opaqueParameterCount)
        return GenericParameterDepthLayout(parameterCountsByDepth: parameterCountsByDepth)
    }

    /// Every context above `descriptor`, innermost first, up to its module;
    /// `nil` when one cannot be read, a parent bound by name to another image
    /// included.
    private static func ancestorsInnermostFirst(of descriptor: OpaqueTypeDescriptor, in context: some ReadingContext) -> [ContextDescriptorWrapper]? {
        var ancestors: [ContextDescriptorWrapper] = []
        do {
            var parentReference = try descriptor.parent(in: context)
            while let currentReference = parentReference {
                guard let parent = currentReference.resolved else { return nil }
                ancestors.append(parent)
                parentReference = try parent.parent(in: context)
            }
        } catch {
            return nil
        }
        return ancestors
    }

    /// The depths the `addedCount` parameters an anonymous context adds span,
    /// outermost first: one, unless the context is a property's sitting in the
    /// module and the property's type is nested in another — a property of
    /// an extension of a nested type, whose type's levels split them. A type
    /// at the top level of its module opens one depth however its property is
    /// declared, and a property in a type's own body sits in that type's
    /// parent, below whatever depths the levels above opened.
    private static func parameterCountsByLevel(addedBy anonymousDescriptor: AnonymousContextDescriptor, addedCount: Int, sitsInModule: Bool, in context: some ReadingContext) -> [Int]? {
        // A property's context exists only under the option that writes its
        // mangled name into it, so a context without one is a function's.
        guard sitsInModule,
              let mangledName = try? anonymousDescriptor.mangledName(in: context),
              mangledName.lookupElements.isEmpty,
              let nameNode = try? demangleAsNodeTransient(mangledName.symbolString),
              let declarationContextNode = propertyNode(named: nameNode)?.children.first
        else { return [addedCount] }
        var typeNode = declarationContextNode.kind == .extension ? declarationContextNode.children.at(1) : declarationContextNode
        if let wrappedTypeNode = typeNode, wrappedTypeNode.kind == .type {
            typeNode = wrappedTypeNode.children.first
        }
        guard let typeNode, let typeContextNode = typeNode.children.first else { return nil }
        // A protocol is one depth, its `Self`, wherever it is declared.
        guard typeContextNode.kind != .module, typeNode.kind != .protocol else { return [addedCount] }
        guard let typeLayout = depthLayout(ofTypeNamed: typeNode, inImageOfDescriptorAt: anonymousDescriptor.offset, in: context),
              typeLayout.parameterCount == addedCount
        else { return nil }
        return typeLayout.parameterCountsByDepth
    }

    /// The `variable` an anonymous context's name stands for, a `static` one
    /// unwrapped; `nil` for a function's, a subscript's or a closure's.
    private static func propertyNode(named nameNode: Node) -> Node? {
        var node = nameNode
        if node.kind == .global, let entityNode = node.children.first {
            node = entityNode
        }
        if node.kind == .static, let memberNode = node.children.first {
            node = memberNode
        }
        return node.kind == .variable ? node : nil
    }

    /// The depth layout of the nominal type `typeNode` names, read from its
    /// descriptor, which its `…Mn` symbol locates: in the image holding the
    /// descriptor at `descriptorOffset`, where a stripped image keeps the
    /// symbol of an exported type alone, and else, for an image loaded in this
    /// process, through the loader — a type another module declares is
    /// public, so its descriptor is exported.
    private static func depthLayout(ofTypeNamed typeNode: Node, inImageOfDescriptorAt descriptorOffset: Int, in context: some ReadingContext) -> GenericParameterDepthLayout? {
        let descriptorSymbolNode = Node.createTransient(kind: .global, children: [Node.createTransient(kind: .nominalTypeDescriptor, children: [typeNode])])
        // The remangled name carries the symbol table's leading underscore.
        guard let lookupContext = context as? any DescriptorSymbolLookupContext,
              let descriptorSymbolName = try? mangleAsString(descriptorSymbolNode)
        else { return nil }
        if let typeDescriptorOffset = lookupContext.offset(ofSymbolNamed: descriptorSymbolName, inImageOfDescriptorAt: descriptorOffset) {
            return depthLayout(ofTypeDescriptorAt: typeDescriptorOffset, in: context)
        }
        // The loader takes the name without the underscore.
        guard lookupContext.readsImageLoadedInProcess, descriptorSymbolName.hasPrefix("_"),
              let typeDescriptorAddress = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, String(descriptorSymbolName.dropFirst()))
        else { return nil }
        return depthLayout(ofTypeDescriptorAt: Int(bitPattern: typeDescriptorAddress), in: InProcessContext.shared)
    }

    private static func depthLayout(ofTypeDescriptorAt offset: Int, in context: some ReadingContext) -> GenericParameterDepthLayout? {
        guard let address = try? context.addressFromOffset(offset),
              let typeDescriptor = try? ContextDescriptorWrapper.resolve(at: address, in: context) as ContextDescriptorWrapper,
              typeDescriptor.isType
        else { return nil }
        return try? make(for: typeDescriptor, in: context)
    }
}

/// A reading context that finds a symbol by name in the image a descriptor
/// it reads belongs to — what `GenericParameterDepthLayout` reaches an
/// extended type's descriptor by.
private protocol DescriptorSymbolLookupContext {
    func offset(ofSymbolNamed name: String, inImageOfDescriptorAt descriptorOffset: Int) -> Int?

    /// Whether the image read is loaded in this process, so that another
    /// image's exported symbol is one `dlsym` away.
    var readsImageLoadedInProcess: Bool { get }
}

extension MachOContext: DescriptorSymbolLookupContext {
    fileprivate func offset(ofSymbolNamed name: String, inImageOfDescriptorAt descriptorOffset: Int) -> Int? {
        SymbolIndexStore.shared.offset(ofSymbolNamed: name, in: machO)
    }

    fileprivate var readsImageLoadedInProcess: Bool {
        machO.asMachOImage != nil
    }
}

extension InProcessContext: DescriptorSymbolLookupContext {
    /// An in-process offset is an address, and the symbol index is kept per
    /// image, keyed from the image's header.
    fileprivate func offset(ofSymbolNamed name: String, inImageOfDescriptorAt descriptorOffset: Int) -> Int? {
        guard let descriptorPointer = UnsafeRawPointer(bitPattern: descriptorOffset),
              let machOImage = MachOImage.image(for: descriptorPointer),
              let imageOffset = SymbolIndexStore.shared.offset(ofSymbolNamed: name, in: machOImage)
        else { return nil }
        return Int(bitPattern: machOImage.ptr) + imageOffset
    }

    fileprivate var readsImageLoadedInProcess: Bool {
        true
    }
}
