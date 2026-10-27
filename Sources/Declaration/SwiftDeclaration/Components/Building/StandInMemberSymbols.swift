import Demangling
import MachOSwiftSection
import OrderedCollections
@_spi(Internals) import MachOSymbols

/// Member symbols that stand in for an implementation symbol the image does
/// not have.
///
/// Every member definition is built from a symbol, and the member builders
/// expect the member's implementation symbol: its own entry point, named by
/// the member's mangling. An optimized image can lack it while keeping
/// another entry point of the same member (evolution proposal
/// `thunk-only-objc-members`):
/// - an `@objc` member whose body the optimizer inlined into its Objective-C
///   thunk (`$s…To`) and whose Swift entry point it then deleted, so the
///   thunk is the only code the member has;
/// - a class initializer whose allocating entry point (`…fC`) was inlined
///   into its callers and deleted, leaving the initializing one (`…fc`).
///
/// A stand-in is shaped like the implementation symbol it replaces — that
/// symbol's mangled name and member tree — at the address of the entry point
/// the image does have. Everything that derives from the name (the export
/// verdict, the ObjC method table join, the thunk attributes) and from the
/// tree (the vtable join, the ABI identity) then reads it as the symbol it
/// replaces. `ClassDispatchLookups.vtableSlotMemberSymbols` builds the same
/// kind of stand-in from a vtable slot's `Tq` (evolution proposal
/// `interface-descriptor-only-vtable-members`).
package enum StandInMemberSymbols {
    /// `memberSymbols` followed by each of `standIns` whose member none of
    /// the symbols before it declares. A real symbol always wins, and among
    /// stand-ins for the same member the first one wins.
    package static func supplementing(_ memberSymbols: [DemangledSymbol], with standIns: [DemangledSymbol]) -> [DemangledSymbol] {
        guard !standIns.isEmpty else { return memberSymbols }
        var declaredEntityKeys = Set(memberSymbols.compactMap(declaredEntityKey(of:)))
        var supplementedSymbols = memberSymbols
        for standIn in standIns {
            guard let entityKey = declaredEntityKey(of: standIn), declaredEntityKeys.insert(entityKey).inserted else { continue }
            supplementedSymbols.append(standIn)
        }
        return supplementedSymbols
    }

    /// The member a symbol declares, keyed structurally: its entity node,
    /// past the marker a merged-function thunk leads with — the builders fold
    /// a thunk onto the member it stands for, so it declares that member as
    /// much as the canonical symbol does.
    package static func declaredEntityKey(of memberSymbol: DemangledSymbol) -> StructuralNodeReferenceKey? {
        let children = memberSymbol.demangledNode.children
        guard let firstChild = children.first else { return nil }
        if firstChild.kind == .mergedFunction {
            return children.second.map(StructuralNodeReferenceKey.init)
        }
        return StructuralNodeReferenceKey(firstChild)
    }

    /// The allocating entry point that an initializer's initializing entry
    /// point (`…fc`) stands in for: the same tree with the `constructor`
    /// entity rewritten to `allocator`, the same name with the `fc` suffix
    /// swapped for `fC`, at the initializing entry point's address. Rewritten
    /// because the builders file an initializer by its allocating entry
    /// point, and because that is what the vtable slot of the initializer, its
    /// ObjC method table entry (`ObjCMemberTable.member(forAllocatorSymbolNamed:)`)
    /// and its ABI identity are keyed by. `nil` for anything that is not an
    /// initializing entry point.
    package static func allocatorStandIn(
        forInitializerSymbol initializerSymbol: DemangledSymbol,
        in machO: some MachORepresentableWithCache
    ) -> DemangledSymbol? {
        guard let constructorNode = initializerSymbol.demangledNode.children.first, constructorNode.kind == .constructor else { return nil }
        return allocatorStandIn(forConstructorNode: constructorNode, initializerName: initializerSymbol.name, offset: initializerSymbol.offset, in: machO)
    }

    /// The implementation symbol an `@objc` thunk (`$s…To`) stands in for:
    /// the thunk's tree without its `objCAttribute` marker, the thunk's name
    /// without its `To` suffix, at the thunk's own address. An initializer's
    /// thunk enters the initializing entry point, so its stand-in is
    /// rewritten further into the allocating one
    /// (`allocatorStandIn(forInitializerSymbol:in:)`). `nil` for anything that
    /// is not an `@objc` thunk of a member.
    package static func memberStandIn(
        forObjCThunkSymbol thunkSymbol: DemangledSymbol,
        in machO: some MachORepresentableWithCache
    ) -> DemangledSymbol? {
        let thunkName = thunkSymbol.name
        guard thunkName.hasSuffix("To"),
              thunkSymbol.demangledNode.children.first?.kind == .objCAttribute,
              let entityNode = thunkSymbol.demangledNode.children.first(where: { $0.kind != .objCAttribute }) else { return nil }
        let implementationName = String(thunkName.dropLast(2))
        if entityNode.kind == .constructor {
            return allocatorStandIn(forConstructorNode: entityNode, initializerName: implementationName, offset: thunkSymbol.offset, in: machO)
        }
        let memberTree = Node.createTransient(kind: .global, child: entityNode.materialize())
        let memberNode = InternedNodeReferenceCache.shared.reference(interning: memberTree, in: machO)
        return DemangledSymbol(symbol: Symbol(offset: thunkSymbol.offset, name: implementationName), demangledNode: memberNode)
    }

    private static func allocatorStandIn(
        forConstructorNode constructorNode: NodeReference,
        initializerName: String,
        offset: Int,
        in machO: some MachORepresentableWithCache
    ) -> DemangledSymbol? {
        guard initializerName.hasSuffix("fc") else { return nil }
        let allocatorEntity = Node.createTransient(kind: .allocator, children: constructorNode.children.map { $0.materialize() })
        let allocatorTree = Node.createTransient(kind: .global, child: allocatorEntity)
        let allocatorNode = InternedNodeReferenceCache.shared.reference(interning: allocatorTree, in: machO)
        let allocatorName = String(initializerName.dropLast(2)) + "fC"
        return DemangledSymbol(symbol: Symbol(offset: offset, name: allocatorName), demangledNode: allocatorNode)
    }
}

extension StandInMemberSymbols {
    /// The stand-ins for one type's own members, by the member builder input
    /// each belongs in, in the order they are tried: the initializing entry
    /// points before the `@objc` thunks, so an initializer that kept its
    /// Swift initializing entry point is located there rather than at its
    /// thunk.
    package struct TypeMembers {
        private var standInsByCategory: [MemberCategory: [DemangledSymbol]] = [:]

        package init(
            typeName: String,
            typeNode: NodeReference,
            symbolIndexStore: SymbolIndexStore,
            in machO: some MachORepresentableWithCache
        ) {
            func thunkStandIns(_ kinds: SymbolIndexStore.MemberKind...) -> [DemangledSymbol] {
                kinds.flatMap { symbolIndexStore.objcThunkMemberSymbols(of: $0, for: typeName, node: typeNode, in: machO) }
                    .compactMap { StandInMemberSymbols.memberStandIn(forObjCThunkSymbol: $0, in: machO) }
            }
            let initializerStandIns = symbolIndexStore.memberSymbols(of: .constructor(inExtension: false), for: typeName, node: typeNode, in: machO)
                .compactMap { StandInMemberSymbols.allocatorStandIn(forInitializerSymbol: $0, in: machO) }
            standInsByCategory[.allocators] = initializerStandIns + thunkStandIns(.constructor(inExtension: false), .allocator(inExtension: false))
            standInsByCategory[.functions] = thunkStandIns(.function(inExtension: false, isStatic: false))
            standInsByCategory[.staticFunctions] = thunkStandIns(.function(inExtension: false, isStatic: true))
            standInsByCategory[.variables] = thunkStandIns(.variable(inExtension: false, isStatic: false, isStorage: false))
            standInsByCategory[.staticVariables] = thunkStandIns(.variable(inExtension: false, isStatic: true, isStorage: false))
            standInsByCategory[.subscripts] = thunkStandIns(.subscript(inExtension: false, isStatic: false))
            standInsByCategory[.staticSubscripts] = thunkStandIns(.subscript(inExtension: false, isStatic: true))
        }

        /// `memberSymbols` plus the stand-ins of `category` whose member none
        /// of them declares.
        package func supplementing(_ memberSymbols: [DemangledSymbol], in category: MemberCategory) -> [DemangledSymbol] {
            StandInMemberSymbols.supplementing(memberSymbols, with: standInsByCategory[category] ?? [])
        }
    }

    /// `memberSymbolsByTypeNode` — the extension members of every type, as
    /// `SymbolIndexStore.memberSymbols(of:excluding:in:)` groups them — plus
    /// the stand-ins of the members none of those symbols declares. A type
    /// whose extension members are all stand-ins gains an entry of its own.
    package static func supplementingExtensionMembers(
        _ memberSymbolsByTypeNode: OrderedDictionary<StructuralNodeReferenceKey, OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]>>,
        symbolIndexStore: SymbolIndexStore,
        in machO: some MachORepresentableWithCache
    ) -> OrderedDictionary<StructuralNodeReferenceKey, OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]>> {
        var standInsByTypeNode: OrderedDictionary<StructuralNodeReferenceKey, OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]>> = [:]
        let initializerSymbolsByTypeNode = symbolIndexStore.memberSymbols(of: .constructor(inExtension: true), excluding: [], in: machO)
        for (typeNodeKey, initializerSymbolsByKind) in initializerSymbolsByTypeNode {
            let standIns = initializerSymbolsByKind.values.joined().compactMap { allocatorStandIn(forInitializerSymbol: $0, in: machO) }
            standInsByTypeNode[typeNodeKey, default: [:]][.allocator(inExtension: true), default: []].append(contentsOf: standIns)
        }
        let thunkSymbolsByTypeNode = symbolIndexStore.objcThunkMemberSymbols(
            of: .constructor(inExtension: true),
            .allocator(inExtension: true),
            .variable(inExtension: true, isStatic: false, isStorage: false),
            .variable(inExtension: true, isStatic: true, isStorage: false),
            .function(inExtension: true, isStatic: false),
            .function(inExtension: true, isStatic: true),
            .subscript(inExtension: true, isStatic: false),
            .subscript(inExtension: true, isStatic: true),
            excluding: [],
            in: machO
        )
        for (typeNodeKey, thunkSymbolsByKind) in thunkSymbolsByTypeNode {
            for (kind, thunkSymbols) in thunkSymbolsByKind {
                let standInKind: SymbolIndexStore.MemberKind = switch kind {
                case .constructor(inExtension: true): .allocator(inExtension: true)
                default: kind
                }
                let standIns = thunkSymbols.compactMap { memberStandIn(forObjCThunkSymbol: $0, in: machO) }
                standInsByTypeNode[typeNodeKey, default: [:]][standInKind, default: []].append(contentsOf: standIns)
            }
        }
        guard !standInsByTypeNode.isEmpty else { return memberSymbolsByTypeNode }
        var supplementedSymbolsByTypeNode = memberSymbolsByTypeNode
        for (typeNodeKey, standInsByKind) in standInsByTypeNode {
            for (kind, standIns) in standInsByKind {
                let memberSymbols = supplementedSymbolsByTypeNode[typeNodeKey]?[kind] ?? []
                let supplementedSymbols = supplementing(memberSymbols, with: standIns)
                guard supplementedSymbols.count > memberSymbols.count else { continue }
                supplementedSymbolsByTypeNode[typeNodeKey, default: [:]][kind] = supplementedSymbols
            }
        }
        return supplementedSymbolsByTypeNode
    }
}
