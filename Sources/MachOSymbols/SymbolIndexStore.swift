import Foundation
import FoundationToolbox
import MachOKit
import MachOExtensions
@_spi(Internals) import Demangling
import OrderedCollections
import Utilities
import Dependencies
import MemberwiseInit
@_spi(Internals) import MachOCaches
import AsyncAlgorithms

@_spi(ForSymbolViewer)
@_spi(Internals)
@Loggable(.private)
public final class SymbolIndexStore: SharedCache<SymbolIndexStore.Storage>, @unchecked Sendable {
    public enum MemberKind: Hashable, CaseIterable, CustomStringConvertible, Sendable {
        fileprivate struct Traits: OptionSet, Hashable, Sendable {
            fileprivate let rawValue: Int
            fileprivate init(rawValue: Int) {
                self.rawValue = rawValue
            }

            fileprivate static let isStatic = Traits(rawValue: 1 << 0)
            fileprivate static let isStorage = Traits(rawValue: 1 << 1)
            fileprivate static let inExtension = Traits(rawValue: 1 << 2)
        }

        case allocator(inExtension: Bool)
        case deallocator
        case constructor(inExtension: Bool)
        case destructor
        case `subscript`(inExtension: Bool, isStatic: Bool)
        case variable(inExtension: Bool, isStatic: Bool, isStorage: Bool)
        case function(inExtension: Bool, isStatic: Bool)

        public static let allCases: [SymbolIndexStore.MemberKind] = [
            .allocator(inExtension: false),
            .allocator(inExtension: true),
            .deallocator,
            .constructor(inExtension: false),
            .constructor(inExtension: true),
            .destructor,
            .subscript(inExtension: false, isStatic: false),
            .subscript(inExtension: false, isStatic: true),
            .subscript(inExtension: true, isStatic: false),
            .subscript(inExtension: true, isStatic: true),
            .variable(inExtension: false, isStatic: false, isStorage: false),
            .variable(inExtension: true, isStatic: true, isStorage: true),
            .variable(inExtension: true, isStatic: false, isStorage: false),
            .variable(inExtension: false, isStatic: true, isStorage: false),
            .variable(inExtension: false, isStatic: false, isStorage: true),
            .variable(inExtension: true, isStatic: true, isStorage: false),
            .variable(inExtension: false, isStatic: true, isStorage: true),
            .variable(inExtension: true, isStatic: false, isStorage: true),
            .function(inExtension: false, isStatic: false),
            .function(inExtension: false, isStatic: true),
            .function(inExtension: true, isStatic: false),
            .function(inExtension: true, isStatic: true),
        ]

        public var description: String {
            switch self {
            case .allocator(inExtension: let inExtension):
                return "Allocator" + (inExtension ? " (In Extension)" : "")
            case .deallocator:
                return "Deallocator"
            case .constructor(inExtension: let inExtension):
                return "Constructor" + (inExtension ? " (In Extension)" : "")
            case .destructor:
                return "Destructor"
            case .subscript(inExtension: let inExtension, isStatic: let isStatic):
                return (isStatic ? "Static " : "") + "Subscript" + (inExtension ? " (In Extension)" : "")
            case .variable(inExtension: let inExtension, isStatic: let isStatic, isStorage: let isStorage):
                return (isStatic ? "Static " : "") + (isStorage ? "Stored " : "") + "Variable" + (inExtension ? " (In Extension)" : "")
            case .function(inExtension: let inExtension, isStatic: let isStatic):
                return (isStatic ? "Static " : "") + "Function" + (inExtension ? " (In Extension)" : "")
            }
        }
    }

    public enum GlobalKind: Hashable, CaseIterable, CustomStringConvertible, Sendable {
        case variable(isStorage: Bool)
        case function

        public static let allCases: [SymbolIndexStore.GlobalKind] = [
            .variable(isStorage: false),
            .variable(isStorage: true),
            .function,
        ]

        public var description: String {
            switch self {
            case .variable(isStorage: let isStorage):
                return (isStorage ? "Stored " : "") + "Global Variable"
            case .function:
                return "Global Function"
            }
        }
    }

    public struct TypeInfo: Sendable {
        public enum Kind: Sendable {
            case `enum`
            case `struct`
            case `class`
            case `protocol`
            case typeAlias
        }

        public let name: String
        public let kind: Kind
    }

    /// Pre-extracted information about a thunk symbol that carries an attribute
    /// annotation (for example `@objc` / `@nonobjc`), bucketed by the printed
    /// name of the type the thunked member belongs to. Consumers use this to
    /// map attribute annotations back onto already-built member definitions
    /// without re-parsing the thunk's demangled node tree per type.
    public struct ThunkAttributeMember: Sendable {
        public let memberName: String
        public let isStatic: Bool
        public let isInit: Bool

        public init(memberName: String, isStatic: Bool, isInit: Bool) {
            self.memberName = memberName
            self.isStatic = isStatic
            self.isInit = isInit
        }
    }

    typealias IndexedSymbol = DemangledSymbol
    typealias AllSymbols = [IndexedSymbol]
    typealias GlobalSymbols = [IndexedSymbol]
    typealias MemberSymbols = OrderedDictionary<String, OrderedDictionary<NodeReference, [IndexedSymbol]>>
    typealias OpaqueTypeDescriptorSymbol = IndexedSymbol

    public final class Storage: @unchecked Sendable {
        /// The frozen arena holding every demangled node of this image.
        /// All `NodeReference` values vended by this storage point into it.
        let nodeStore: NodeStore

        private(set) var typeInfoByName: [String: TypeInfo] = [:]

        private(set) var globalSymbolsByKind: OrderedDictionary<GlobalKind, GlobalSymbols> = [:]

        private(set) var opaqueTypeDescriptorSymbolByNode: OrderedDictionary<NodeReference, OpaqueTypeDescriptorSymbol> = [:]

        private(set) var memberSymbolsByKind: OrderedDictionary<MemberKind, MemberSymbols> = [:]

        private(set) var methodDescriptorMemberSymbolsByKind: OrderedDictionary<MemberKind, MemberSymbols> = [:]

        private(set) var protocolWitnessMemberSymbolsByKind: OrderedDictionary<MemberKind, MemberSymbols> = [:]

        private(set) var symbolsByKind: OrderedDictionary<Node.Kind, AllSymbols> = [:]

        private(set) var symbolsByOffset: OrderedDictionary<Int, [Symbol]> = [:]

        private(set) var demangledNodeBySymbol: [Symbol: NodeReference] = [:]

        /// Symbols demangled after the store was frozen (rare path: lookups
        /// for symbols that were not part of the build sweep). The frozen
        /// arena cannot grow, so each late symbol gets a per-symbol mini
        /// store; the volume is small and every consumer keeps receiving a
        /// uniform `NodeReference`.
        @Mutex
        private(set) var lateDemangledNodeBySymbol: [Symbol: NodeReference] = [:]

        private(set) var thunkAttributeMembersByKindAndTypeName: [Node.Kind: [String: [ThunkAttributeMember]]] = [:]

        fileprivate init(nodeStore: NodeStore) {
            self.nodeStore = nodeStore
        }

        fileprivate func setLateDemangledNode(_ demangledNode: NodeReference?, for symbol: Symbol) {
            lateDemangledNodeBySymbol[symbol] = demangledNode
        }

        /// One-shot population after `freeze()`: converts the build-time
        /// `NodeIndex`-keyed scratch into `NodeReference`-based indexes.
        fileprivate func populate(from pending: PendingStorage, symbolsByOffset: OrderedDictionary<Int, [Symbol]>) {
            func demangledSymbol(_ pendingSymbol: PendingDemangledSymbol) -> DemangledSymbol {
                DemangledSymbol(symbol: pendingSymbol.symbol, demangledNode: nodeStore.reference(at: pendingSymbol.rootNodeIndex))
            }
            func memberSymbols(_ pendingMemberSymbols: PendingStorage.MemberSymbols) -> MemberSymbols {
                var converted: MemberSymbols = [:]
                for (typeName, symbolsByTypeNodeIndex) in pendingMemberSymbols {
                    var convertedByTypeNode: OrderedDictionary<NodeReference, [IndexedSymbol]> = [:]
                    for (typeNodeIndex, pendingSymbols) in symbolsByTypeNodeIndex {
                        convertedByTypeNode[nodeStore.reference(at: typeNodeIndex)] = pendingSymbols.map(demangledSymbol)
                    }
                    converted[typeName] = convertedByTypeNode
                }
                return converted
            }

            typeInfoByName = pending.typeInfoByName
            globalSymbolsByKind = pending.globalSymbolsByKind.mapValues { $0.map(demangledSymbol) }
            opaqueTypeDescriptorSymbolByNode = .init(uniqueKeysWithValues: pending.opaqueTypeDescriptorSymbolByNodeIndex.map { (nodeStore.reference(at: $0.key), demangledSymbol($0.value)) })
            memberSymbolsByKind = pending.memberSymbolsByKind.mapValues(memberSymbols)
            methodDescriptorMemberSymbolsByKind = pending.methodDescriptorMemberSymbolsByKind.mapValues(memberSymbols)
            protocolWitnessMemberSymbolsByKind = pending.protocolWitnessMemberSymbolsByKind.mapValues(memberSymbols)
            symbolsByKind = pending.symbolsByKind.mapValues { $0.map(demangledSymbol) }
            demangledNodeBySymbol = pending.demangledNodeIndexBySymbol.mapValues { nodeStore.reference(at: $0) }
            thunkAttributeMembersByKindAndTypeName = pending.thunkAttributeMembersByKindAndTypeName
            self.symbolsByOffset = symbolsByOffset
        }
    }

    /// A `(symbol, root node index)` pair collected while the builder is still
    /// mutable; becomes a `DemangledSymbol` once the store is frozen.
    fileprivate struct PendingDemangledSymbol: Sendable {
        let symbol: Symbol
        let rootNodeIndex: NodeStore.NodeIndex
    }

    /// Build-time scratch mirroring `Storage`'s indexes with `NodeIndex` keys
    /// and `PendingDemangledSymbol` entries. Lives only for the duration of
    /// `buildStorageImpl`; converted via `Storage.populate(from:symbolsByOffset:)`.
    fileprivate struct PendingStorage {
        typealias MemberSymbols = OrderedDictionary<String, OrderedDictionary<NodeStore.NodeIndex, [PendingDemangledSymbol]>>

        var typeInfoByName: [String: TypeInfo] = [:]
        var globalSymbolsByKind: OrderedDictionary<GlobalKind, [PendingDemangledSymbol]> = [:]
        var opaqueTypeDescriptorSymbolByNodeIndex: OrderedDictionary<NodeStore.NodeIndex, PendingDemangledSymbol> = [:]
        var memberSymbolsByKind: OrderedDictionary<MemberKind, MemberSymbols> = [:]
        var methodDescriptorMemberSymbolsByKind: OrderedDictionary<MemberKind, MemberSymbols> = [:]
        var protocolWitnessMemberSymbolsByKind: OrderedDictionary<MemberKind, MemberSymbols> = [:]
        var symbolsByKind: OrderedDictionary<Node.Kind, [PendingDemangledSymbol]> = [:]
        var demangledNodeIndexBySymbol: [Symbol: NodeStore.NodeIndex] = [:]
        var thunkAttributeMembersByKindAndTypeName: [Node.Kind: [String: [ThunkAttributeMember]]] = [:]

        mutating func appendSymbol(_ pendingSymbol: PendingDemangledSymbol, for kind: Node.Kind) {
            symbolsByKind[kind, default: []].append(pendingSymbol)
        }

        mutating func setMemberSymbols(for result: ProcessMemberSymbolResult) {
            memberSymbolsByKind[result.memberKind, default: [:]][result.typeName, default: [:]][result.typeNodeIndex, default: []].append(result.pendingSymbol)
            typeInfoByName[result.typeName] = result.typeInfo
        }

        mutating func setMethodDescriptorMemberSymbols(for result: ProcessMemberSymbolResult) {
            methodDescriptorMemberSymbolsByKind[result.memberKind, default: [:]][result.typeName, default: [:]][result.typeNodeIndex, default: []].append(result.pendingSymbol)
            typeInfoByName[result.typeName] = result.typeInfo
        }

        mutating func setProtocolWitnessMemberSymbols(for result: ProcessMemberSymbolResult) {
            protocolWitnessMemberSymbolsByKind[result.memberKind, default: [:]][result.typeName, default: [:]][result.typeNodeIndex, default: []].append(result.pendingSymbol)
            typeInfoByName[result.typeName] = result.typeInfo
        }

        mutating func setGlobalSymbols(for result: ProcessGlobalSymbolResult) {
            globalSymbolsByKind[result.kind, default: []].append(result.pendingSymbol)
        }

        mutating func appendThunkAttributeMember(_ member: ThunkAttributeMember, forKind thunkKind: Node.Kind, typeName: String) {
            thunkAttributeMembersByKindAndTypeName[thunkKind, default: [:]][typeName, default: []].append(member)
        }
    }

    public static let shared = SymbolIndexStore()

    private override init() {
        super.init()
    }

    public override func buildStorage<MachO: MachORepresentableWithCache>(for machO: MachO) -> Storage? {
        return buildStorageImpl(for: machO, progressContinuation: nil)
    }

    private func buildStorageImpl<MachO: MachORepresentableWithCache>(
        for machO: MachO,
        progressContinuation: AsyncStream<Progress>.Continuation?
    ) -> Storage? {
        var cachedSymbols: Set<String> = []
        var symbolByName: OrderedDictionary<String, Symbol> = [:]
        var symbolsByOffset: OrderedDictionary<Int, [Symbol]> = [:]

        for symbol in machO.symbols where symbol.name.isSwiftSymbol && !symbol.nlist.isExternal {
            var offset = symbol.offset
            symbolsByOffset[offset, default: []].append(.init(offset: offset, name: symbol.name, nlist: symbol.nlist))
            if let cache = machO.cache, offset >= 0, machO is MachOFile {
                offset -= cache.mainCacheHeader.sharedRegionStart.cast()
                symbolsByOffset[offset, default: []].append(.init(offset: offset, name: symbol.name, nlist: symbol.nlist))
            }
            symbolByName[symbol.name] = .init(offset: offset, name: symbol.name, nlist: symbol.nlist)
            cachedSymbols.insert(symbol.name)
        }

        for exportedSymbol in machO.exportedSymbols where exportedSymbol.name.isSwiftSymbol {
            if var offset = exportedSymbol.offset, symbolByName[exportedSymbol.name] == nil {
                symbolsByOffset[offset, default: []].append(.init(offset: offset, name: exportedSymbol.name))
                if machO is MachOFile {
                    offset += machO.startOffset
                }
                symbolsByOffset[offset, default: []].append(.init(offset: offset, name: exportedSymbol.name))
                symbolByName[exportedSymbol.name] = .init(offset: offset, name: exportedSymbol.name)
            }
        }

        // Single sequential sweep: demangle each symbol cache-free onto a
        // transient tree, classify on that tree, and intern the result into
        // the arena builder. Nothing touches the global `NodeCache` and no
        // class trees outlive the loop iteration (NodeStore migration plan,
        // Stage 1). The former concurrentMap pipeline kept every class tree
        // alive simultaneously and leaked all of them into `NodeCache.shared`.
        let symbolArray = Array(symbolByName.values)
        let totalSymbolCount = symbolArray.count

        var builder = NodeStoreBuilder()
        var pending = PendingStorage()
        pending.demangledNodeIndexBySymbol.reserveCapacity(totalSymbolCount)

        for symbolIndex in 0..<totalSymbolCount {
            if symbolIndex % 500 == 0 {
                progressContinuation?.yield(Progress(currentCount: symbolIndex, totalCount: totalSymbolCount))
            }

            let symbol = symbolArray[symbolIndex]
            guard let rootNode = try? demangleAsNodeTransient(symbol.name) else { continue }
            let rootNodeIndex = builder.intern(rootNode)
            let pendingSymbol = PendingDemangledSymbol(symbol: symbol, rootNodeIndex: rootNodeIndex)

            pending.demangledNodeIndexBySymbol[symbol] = rootNodeIndex

            guard rootNode.isKind(of: .global), let node = rootNode.children.first else { continue }

            pending.appendSymbol(pendingSymbol, for: node.kind)

            if node.kind == .objCAttribute || node.kind == .nonObjCAttribute {
                if let extracted = processThunkAttributeSymbol(thunkKind: node.kind, rootNode: rootNode) {
                    pending.appendThunkAttributeMember(extracted.member, forKind: node.kind, typeName: extracted.typeName)
                }
                continue
            }

            if rootNode.isGlobal {
                if !symbol.isExternal {
                    if let result = processGlobalSymbol(pendingSymbol, node: node) {
                        pending.setGlobalSymbols(for: result)
                    }
                }
            } else {
                if node.kind == .methodDescriptor, let firstChild = node.children.first {
                    if let result = processMemberSymbol(pendingSymbol, node: firstChild, builder: &builder) {
                        pending.setMethodDescriptorMemberSymbols(for: result)
                    }
                } else if node.kind == .protocolWitness, let firstChild = node.children.first {
                    if let result = processMemberSymbol(pendingSymbol, node: firstChild, builder: &builder) {
                        pending.setProtocolWitnessMemberSymbols(for: result)
                    }
                } else if node.kind == .mergedFunction, let secondChild = rootNode.children.second {
                    if let result = processMemberSymbol(pendingSymbol, node: secondChild, builder: &builder) {
                        pending.setMemberSymbols(for: result)
                    }
                } else if node.kind == .opaqueTypeDescriptor, let firstChild = node.children.first, firstChild.kind == .opaqueReturnTypeOf, let memberSymbol = firstChild.children.first {
                    if symbol.offset > 0 {
                        pending.opaqueTypeDescriptorSymbolByNodeIndex[builder.intern(memberSymbol)] = pendingSymbol
                    }
                } else {
                    if let result = processMemberSymbol(pendingSymbol, node: node, builder: &builder) {
                        pending.setMemberSymbols(for: result)
                    }
                }
            }
        }
        progressContinuation?.yield(Progress(currentCount: totalSymbolCount, totalCount: totalSymbolCount))

        let storage = Storage(nodeStore: builder.freeze())
        storage.populate(from: pending, symbolsByOffset: symbolsByOffset)

        return storage
    }

    fileprivate struct ProcessMemberSymbolResult: Sendable {
        let memberKind: MemberKind
        let typeName: String
        let typeNodeIndex: NodeStore.NodeIndex
        let typeInfo: TypeInfo
        let pendingSymbol: PendingDemangledSymbol
    }

    private func processMemberSymbol(_ pendingSymbol: PendingDemangledSymbol, node: Node, builder: inout NodeStoreBuilder) -> ProcessMemberSymbolResult? {
        if node.kind == .static, let firstChild = node.children.first, firstChild.kind.isMember {
            return processMemberSymbol(pendingSymbol, node: firstChild, traits: [.isStatic], builder: &builder)
        } else if node.kind.isMember {
            return processMemberSymbol(pendingSymbol, node: node, traits: [], builder: &builder)
        }
        return nil
    }

    private func processMemberSymbol(_ pendingSymbol: PendingDemangledSymbol, node: Node, traits: MemberKind.Traits, builder: inout NodeStoreBuilder) -> ProcessMemberSymbolResult? {
        var traits = traits
        let node = node
        switch node.kind {
        case .allocator:
            guard var first = node.children.first else { return nil }
            if first.kind == .extension, let type = first.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            return processMemberSymbol(pendingSymbol, node: first, memberKind: .allocator(inExtension: traits.contains(.inExtension)), builder: &builder)
        case .deallocator:
            guard let first = node.children.first else { return nil }
            return processMemberSymbol(pendingSymbol, node: first, memberKind: .deallocator, builder: &builder)
        case .constructor:
            guard var first = node.children.first else { return nil }
            if first.kind == .extension, let type = first.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            return processMemberSymbol(pendingSymbol, node: first, memberKind: .constructor(inExtension: traits.contains(.inExtension)), builder: &builder)
        case .destructor:
            guard let first = node.children.first else { return nil }
            return processMemberSymbol(pendingSymbol, node: first, memberKind: .destructor, builder: &builder)
        case .function:
            guard var first = node.children.first else { return nil }
            if first.kind == .extension, let type = first.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            return processMemberSymbol(pendingSymbol, node: first, memberKind: .function(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic)), builder: &builder)
        case .variable:
            // Stored variable reached directly (not through getter/setter)
            traits.insert(.isStorage)
            var first = node.children.first
            if first?.kind == .extension, let type = first?.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            if let first {
                return processMemberSymbol(pendingSymbol, node: first, memberKind: .variable(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic), isStorage: traits.contains(.isStorage)), builder: &builder)
            }
        case .getter,
             .setter:
            if let variableNode = node.children.first, variableNode.kind == .variable, var first = variableNode.children.first {
                if first.kind == .extension, let type = first.children.at(1) {
                    traits.insert(.inExtension)
                    first = type
                }
                return processMemberSymbol(pendingSymbol, node: first, memberKind: .variable(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic), isStorage: traits.contains(.isStorage)), builder: &builder)
            } else if let subscriptNode = node.children.first, subscriptNode.kind == .subscript, var first = subscriptNode.children.first {
                if first.kind == .extension, let type = first.children.at(1) {
                    traits.insert(.inExtension)
                    first = type
                }
                return processMemberSymbol(pendingSymbol, node: first, memberKind: .subscript(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic)), builder: &builder)
            }
        default:
            break
        }
        return nil
    }

    private func processMemberSymbol(_ pendingSymbol: PendingDemangledSymbol, node: Node, memberKind: MemberKind, builder: inout NodeStoreBuilder) -> ProcessMemberSymbolResult? {
        if let typeKind = node.kind.typeKind {
            // The transient `.type` wrapper exists only for printing; the
            // arena-resident wrapper is built directly from the interned
            // context node's index, so no class tree survives this call.
            let typeName = Node.create(kind: .type, child: node).print(using: .interfaceTypeBuilderOnly)
            let typeNodeIndex = builder.intern(kind: .type, children: [builder.intern(node)])
            return .init(memberKind: memberKind, typeName: typeName, typeNodeIndex: typeNodeIndex, typeInfo: .init(name: typeName, kind: typeKind), pendingSymbol: pendingSymbol)
        }
        return nil
    }

    /// Extracts `(typeName, ThunkAttributeMember)` from a thunk symbol whose root
    /// demangled node has an attribute marker child (`.objCAttribute` /
    /// `.nonObjCAttribute`). Returns `nil` if the thunk does not wrap a named
    /// member whose parent context can be resolved to a Swift type name.
    private func processThunkAttributeSymbol(
        thunkKind: Node.Kind,
        rootNode: Node
    ) -> (typeName: String, member: ThunkAttributeMember)? {
        guard let memberNode = rootNode.children.first(where: { $0.kind != thunkKind }) else { return nil }

        let isStatic: Bool
        let unwrappedMemberNode: Node
        if memberNode.kind == .static, let innerChild = memberNode.children.first {
            isStatic = true
            unwrappedMemberNode = innerChild
        } else {
            isStatic = false
            unwrappedMemberNode = memberNode
        }

        let extractedMemberName: String?
        let contextNode: Node?

        switch unwrappedMemberNode.kind {
        case .function, .constructor, .allocator, .variable:
            contextNode = unwrappedMemberNode.children.first.map(Self.unwrapExtensionContext)
            extractedMemberName = unwrappedMemberNode.identifier
        case .getter, .setter:
            if let innerVariable = unwrappedMemberNode.children.first, innerVariable.kind == .variable {
                contextNode = innerVariable.children.first.map(Self.unwrapExtensionContext)
                extractedMemberName = innerVariable.identifier
            } else {
                return nil
            }
        default:
            return nil
        }

        guard let contextNode, let extractedMemberName else { return nil }

        let typeName = Node.create(kind: .type, child: contextNode).print(using: .interfaceTypeBuilderOnly)

        let isInit = unwrappedMemberNode.kind == .allocator || unwrappedMemberNode.kind == .constructor

        return (
            typeName: typeName,
            member: ThunkAttributeMember(memberName: extractedMemberName, isStatic: isStatic, isInit: isInit)
        )
    }

    /// If the given node is an `.extension` wrapper, return the extended type node
    /// (the second child, per Swift demangler's extension node layout:
    /// `extension(module, extendedType, ?genericSignature)`). Otherwise, return
    /// the node as-is.
    private static func unwrapExtensionContext(_ node: Node) -> Node {
        if node.kind == .extension, let extendedType = node.children.at(1) {
            return extendedType
        }
        return node
    }

    fileprivate struct ProcessGlobalSymbolResult: Sendable {
        let kind: GlobalKind
        let pendingSymbol: PendingDemangledSymbol
    }

    private func processGlobalSymbol(_ pendingSymbol: PendingDemangledSymbol, node: Node) -> ProcessGlobalSymbolResult? {
        switch node.kind {
        case .function:
            return .init(kind: .function, pendingSymbol: pendingSymbol)
        case .variable:
            // When we reach .variable directly (not through getter/setter),
            // this is a stored variable declaration
            return .init(kind: .variable(isStorage: true), pendingSymbol: pendingSymbol)
        case .getter,
             .setter:
            if let variableNode = node.children.first, variableNode.kind == .variable {
                return processGlobalSymbol(pendingSymbol, node: variableNode)
            }
        default:
            break
        }
        return nil
    }

    public func allSymbols<MachO: MachORepresentableWithCache>(in machO: MachO) -> [DemangledSymbol] {
        if let symbols = storage(in: machO)?.symbolsByKind.values.flatMap({ $0 }) {
            return symbols
        } else {
            return []
        }
    }

    public func symbolsByKind<MachO: MachORepresentableWithCache>(in machO: MachO) -> OrderedDictionary<Node.Kind, [DemangledSymbol]> {
        if let symbols = storage(in: machO)?.symbolsByKind {
            return symbols.mapValues { $0 }
        } else {
            return [:]
        }
    }

    public func typeInfo<MachO: MachORepresentableWithCache>(for name: String, in machO: MachO) -> TypeInfo? {
        return storage(in: machO)?.typeInfoByName[name]
    }

    public func symbols<MachO: MachORepresentableWithCache>(of kinds: Node.Kind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.symbolsByKind[$0] ?? [] }.reduce(into: []) { $0 += $1 }
    }

    /// Returns the pre-extracted thunk-attribute members whose parent type
    /// name matches `typeName`. `thunkKind` is the demangler attribute marker
    /// kind (e.g. `.objCAttribute`, `.nonObjCAttribute`). Lookup is O(1) in the
    /// typeName bucket; no per-type scan of all thunk symbols is needed.
    public func thunkAttributeMembers<MachO: MachORepresentableWithCache>(
        of thunkKind: Node.Kind,
        for typeName: String,
        in machO: MachO
    ) -> [ThunkAttributeMember] {
        return storage(in: machO)?.thunkAttributeMembersByKindAndTypeName[thunkKind]?[typeName] ?? []
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.memberSymbolsByKind[$0]?.values.flatMap { $0.values.flatMap { $0 } } ?? [] }.reduce(into: []) { $0 += $1 }
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.memberSymbolsByKind[$0]?[name]?.values.flatMap { $0 } ?? [] }.reduce(into: []) { $0 += $1 }
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, node: Node, in machO: MachO) -> [DemangledSymbol] {
        // Callers hold an externally demangled `Node` (MetadataReader context
        // demangling), while keys are `NodeReference`s into the frozen store.
        // The type-name bucket holds at most a handful of type nodes, so a
        // structural walk per key is cheap.
        return kinds.map { kind -> [DemangledSymbol] in
            guard let symbolsByTypeNode = storage(in: machO)?.memberSymbolsByKind[kind]?[name] else { return [] }
            return symbolsByTypeNode.elements.first(where: { $0.key.structurallyEquals(node) })?.value ?? []
        }.reduce(into: []) { $0 += $1 }
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., excluding names: borrowing Set<String>, in machO: MachO) -> OrderedDictionary<NodeReference, OrderedDictionary<MemberKind, [DemangledSymbol]>> {
        let filtered: OrderedDictionary<MemberKind, MemberSymbols> = kinds.reduce(into: [:]) { $0[$1] = storage(in: machO)?.memberSymbolsByKind[$1]?.filter { !names.contains($0.key) } ?? [:] }

        var result: OrderedDictionary<NodeReference, OrderedDictionary<MemberKind, [DemangledSymbol]>> = [:]
        for (kind, memberSymbols) in filtered {
            for (_, symbols) in memberSymbols {
                for (node, symbols) in symbols {
                    result[node, default: [:]][kind, default: []].append(contentsOf: symbols)
                }
            }
        }
        return result
    }

    public func methodDescriptorMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.methodDescriptorMemberSymbolsByKind[$0]?.values.flatMap { $0.values.flatMap { $0 } } ?? [] }.reduce(into: []) { $0 += $1 }
    }

    public func methodDescriptorMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.methodDescriptorMemberSymbolsByKind[$0]?[name]?.values.flatMap { $0 } ?? [] }.reduce(into: []) { $0 += $1 }
    }

    public func protocolWitnessMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.protocolWitnessMemberSymbolsByKind[$0]?.values.flatMap { $0.values.flatMap { $0 } } ?? [] }.reduce(into: []) { $0 += $1 }
    }

    public func protocolWitnessMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.protocolWitnessMemberSymbolsByKind[$0]?[name]?.values.flatMap { $0 } ?? [] }.reduce(into: []) { $0 += $1 }
    }

    public func globalSymbols<MachO: MachORepresentableWithCache>(of kinds: GlobalKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.globalSymbolsByKind[$0] ?? [] }.reduce(into: []) { $0 += $1 }
    }

    public func allOpaqueTypeDescriptorSymbols<MachO: MachORepresentableWithCache>(in machO: MachO) -> OrderedDictionary<NodeReference, DemangledSymbol>? {
        return storage(in: machO)?.opaqueTypeDescriptorSymbolByNode.mapValues {
            return $0
        }
    }

    public func opaqueTypeDescriptorSymbol<MachO: MachORepresentableWithCache>(for node: Node, in machO: MachO) -> DemangledSymbol? {
        // The caller's `node` was demangled during printing; keys live in the
        // frozen store. Structural comparison early-outs on the first
        // mismatching kind, so the linear scan stays cheap relative to the
        // printing work that triggers it.
        return storage(in: machO)?.opaqueTypeDescriptorSymbolByNode.elements.first(where: { $0.key.structurallyEquals(node) })?.value
    }

    package func symbols<MachO: MachORepresentableWithCache>(for offset: Int, in machO: MachO) -> Symbols? {
        if let symbols = storage(in: machO)?.symbolsByOffset[offset], !symbols.isEmpty {
            return .init(offset: offset, symbols: symbols)
        } else {
            return nil
        }
    }

    /// Store-backed handle for a symbol's demangled tree. Hits the frozen
    /// image store for symbols covered by the build sweep; symbols outside
    /// the sweep are demangled cache-free into a per-symbol mini store, so
    /// every caller receives a uniform `NodeReference`.
    package func demangledNodeReference<MachO: MachORepresentableWithCache>(for symbol: Symbol, in machO: MachO) -> NodeReference? {
        guard let cacheStorage = storage(in: machO) else { return nil }
        if let reference = cacheStorage.demangledNodeBySymbol[symbol] {
            return reference
        }
        if let reference = cacheStorage.lateDemangledNodeBySymbol[symbol] {
            return reference
        }
        var lateBuilder = NodeStoreBuilder()
        guard let nodeIndex = try? lateBuilder.demangle(symbol.name) else { return nil }
        let reference = lateBuilder.freeze().reference(at: nodeIndex)
        cacheStorage.setLateDemangledNode(reference, for: symbol)
        return reference
    }

    package func demangledNode<MachO: MachORepresentableWithCache>(for symbol: Symbol, in machO: MachO) -> Node? {
        return demangledNodeReference(for: symbol, in: machO)?.materialize()
    }

    public struct Progress: Sendable {
        public let currentCount: Int
        public let totalCount: Int
    }

    public func prepare<MachO: MachORepresentableWithCache>(in machO: MachO) {
        _ = storage(in: machO)
    }

    public func prepareWithProgress<MachO: MachORepresentableWithCache>(in machO: MachO) -> AsyncStream<Progress> {
        let (stream, continuation) = AsyncStream<Progress>.makeStream()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { continuation.finish() }
            guard let self else { return }
            // continuation flows into buildStorageImpl via closure capture only.
            // No shared instance state is involved, so concurrent calls cannot
            // interfere with each other's progress streams.
            _ = self.storage(in: machO) { machO in
                self.buildStorageImpl(for: machO, progressContinuation: continuation)
            }
        }
        return stream
    }
}

extension Node.Kind {
    fileprivate var isMember: Bool {
        switch self {
        case .allocator,
             .deallocator,
             .constructor,
             .destructor,
             .function,
             .getter,
             .setter,
             .methodDescriptor,
             .protocolWitness,
             .variable:
            return true
        default:
            return false
        }
    }

    fileprivate var typeKind: SymbolIndexStore.TypeInfo.Kind? {
        switch self {
        case .enum:
            return .enum
        case .structure:
            return .struct
        case .class:
            return .class
        case .protocol:
            return .protocol
        case .typeAlias:
            return .typeAlias
        default:
            return nil
        }
    }
}

private enum SymbolIndexStoreKey: DependencyKey {
    static let liveValue: SymbolIndexStore = .shared
    static let testValue: SymbolIndexStore = .shared
}

@_spi(ForSymbolViewer)
@_spi(Internals)
extension DependencyValues {
    public var symbolIndexStore: SymbolIndexStore {
        get { self[SymbolIndexStoreKey.self] }
        set { self[SymbolIndexStoreKey.self] = newValue }
    }
}

extension DemanglingNode {
    package var isGlobal: Bool {
        guard let first = children.first else { return false }
        guard first.isKind(of: .getter, .setter, .function, .variable) else { return false }
        if first.isKind(of: .getter, .setter), let variable = first.children.first, variable.isKind(of: .variable) {
            return variable.children.first?.isKind(of: .module) ?? false
        } else {
            return first.children.first?.isKind(of: .module) ?? false
        }
    }

    package var isAccessor: Bool {
        return isKind(of: .getter, .setter, .modifyAccessor, .readAccessor)
    }
}

extension DemanglingNode where Self: Sequence<Self> {
    package var hasAccessor: Bool {
        return contains { $0.isAccessor }
    }
}

extension Symbol {
    package var isExternal: Bool {
        nlist?.isExternal ?? false
    }
}

extension NlistProtocol {
    package var isExternal: Bool {
        guard let flags = flags, let type = flags.type else { return false }
        return flags.contains(.ext) && type == .undf
    }
}
