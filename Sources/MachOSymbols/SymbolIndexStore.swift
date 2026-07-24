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

    public final class Storage: @unchecked Sendable {
        typealias MemberSymbolRows = OrderedDictionary<String, OrderedDictionary<NodeStore.NodeIndex, [UInt32]>>

        /// The frozen arena holding every demangled node of this image.
        /// All `NodeReference` values vended by this storage point into it.
        let nodeStore: NodeStore

        /// Flat symbol table (Stage 3): one row per unique symbol name,
        /// holding the canonical (cache-adjusted) offset. Every index below
        /// stores 4-byte row indices into this table instead of inline
        /// `Symbol` copies, and vended `DemangledSymbol` values share this
        /// array's buffer.
        let symbolTable: [Symbol]

        /// Parallel to `symbolTable`: the row's demangled root node, or
        /// `nil` for names the demangler rejected (those still occupy a row
        /// because `symbolRowsByOffset` references them).
        let rootNodeIndexByTableRow: [NodeStore.NodeIndex?]

        /// Name → table row. Keys share string storage with `symbolTable`.
        let tableRowByName: [String: UInt32]

        let typeInfoByName: [String: TypeInfo]

        let globalSymbolRowsByKind: OrderedDictionary<GlobalKind, [UInt32]>

        let opaqueTypeDescriptorSymbolRowByNodeIndex: OrderedDictionary<NodeStore.NodeIndex, UInt32>

        let memberSymbolRowsByKind: OrderedDictionary<MemberKind, MemberSymbolRows>

        let methodDescriptorMemberSymbolRowsByKind: OrderedDictionary<MemberKind, MemberSymbolRows>

        let protocolWitnessMemberSymbolRowsByKind: OrderedDictionary<MemberKind, MemberSymbolRows>

        let symbolRowsByKind: OrderedDictionary<Node.Kind, [UInt32]>

        let symbolRowsByOffset: OrderedDictionary<Int, [UInt32]>

        let thunkAttributeMembersByKindAndTypeName: [Node.Kind: [String: [ThunkAttributeMember]]]

        /// Symbols demangled after the store was frozen (rare path: lookups
        /// for symbols that were not part of the build sweep). The frozen
        /// arena cannot grow, so each late symbol gets a per-symbol mini
        /// store; the volume is small and every consumer keeps receiving a
        /// uniform `NodeReference`.
        @Mutex
        private(set) var lateDemangledNodeBySymbol: [Symbol: NodeReference] = [:]

        fileprivate init(
            nodeStore: NodeStore,
            symbolTable: [Symbol],
            rootNodeIndexByTableRow: [NodeStore.NodeIndex?],
            tableRowByName: [String: UInt32],
            symbolRowsByOffset: OrderedDictionary<Int, [UInt32]>,
            rowIndexes: consuming RowIndexes
        ) {
            self.nodeStore = nodeStore
            self.symbolTable = symbolTable
            self.rootNodeIndexByTableRow = rootNodeIndexByTableRow
            self.tableRowByName = tableRowByName
            self.symbolRowsByOffset = symbolRowsByOffset
            self.typeInfoByName = rowIndexes.typeInfoByName
            self.globalSymbolRowsByKind = rowIndexes.globalSymbolRowsByKind
            self.opaqueTypeDescriptorSymbolRowByNodeIndex = rowIndexes.opaqueTypeDescriptorSymbolRowByNodeIndex
            self.memberSymbolRowsByKind = rowIndexes.memberSymbolRowsByKind
            self.methodDescriptorMemberSymbolRowsByKind = rowIndexes.methodDescriptorMemberSymbolRowsByKind
            self.protocolWitnessMemberSymbolRowsByKind = rowIndexes.protocolWitnessMemberSymbolRowsByKind
            self.symbolRowsByKind = rowIndexes.symbolRowsByKind
            self.thunkAttributeMembersByKindAndTypeName = rowIndexes.thunkAttributeMembersByKindAndTypeName
        }

        fileprivate func setLateDemangledNode(_ demangledNode: NodeReference?, for symbol: Symbol) {
            lateDemangledNodeBySymbol[symbol] = demangledNode
        }

        // MARK: Row materialization

        /// Rebuilds the `Symbol` for an offset-table row using the queried
        /// offset: raw and cache-adjusted keys share one canonical row, so
        /// the row's stored offset is not necessarily the queried one.
        fileprivate func symbol(atRow row: UInt32, offset queriedOffset: Int) -> Symbol {
            let canonicalSymbol = symbolTable[Int(row)]
            return Symbol(offset: queriedOffset, name: canonicalSymbol.name, isExternal: canonicalSymbol.isExternal)
        }

        func demangledSymbol(atRow row: UInt32) -> DemangledSymbol? {
            guard let rootNodeIndex = rootNodeIndexByTableRow[Int(row)] else { return nil }
            return DemangledSymbol(symbolTable: symbolTable, symbolTableRow: row, demangledNode: nodeStore.reference(at: rootNodeIndex))
        }

        func demangledSymbols(atRows rows: [UInt32]) -> [DemangledSymbol] {
            rows.compactMap { demangledSymbol(atRow: $0) }
        }
    }

    /// Build-time accumulator holding the row-index form of `Storage`'s
    /// classification indexes. `Storage.init` moves these dictionaries in
    /// unchanged — there is no post-freeze conversion pass, so the former
    /// pending→populate double-index transient peak is gone (Stage 3).
    fileprivate struct RowIndexes {
        var typeInfoByName: [String: TypeInfo] = [:]
        var globalSymbolRowsByKind: OrderedDictionary<GlobalKind, [UInt32]> = [:]
        var opaqueTypeDescriptorSymbolRowByNodeIndex: OrderedDictionary<NodeStore.NodeIndex, UInt32> = [:]
        var memberSymbolRowsByKind: OrderedDictionary<MemberKind, Storage.MemberSymbolRows> = [:]
        var methodDescriptorMemberSymbolRowsByKind: OrderedDictionary<MemberKind, Storage.MemberSymbolRows> = [:]
        var protocolWitnessMemberSymbolRowsByKind: OrderedDictionary<MemberKind, Storage.MemberSymbolRows> = [:]
        var symbolRowsByKind: OrderedDictionary<Node.Kind, [UInt32]> = [:]
        var thunkAttributeMembersByKindAndTypeName: [Node.Kind: [String: [ThunkAttributeMember]]] = [:]

        mutating func appendSymbolRow(_ symbolTableRow: UInt32, for kind: Node.Kind) {
            symbolRowsByKind[kind, default: []].append(symbolTableRow)
        }

        mutating func setMemberSymbols(for result: ProcessMemberSymbolResult) {
            memberSymbolRowsByKind[result.memberKind, default: [:]][result.typeName, default: [:]][result.typeNodeIndex, default: []].append(result.symbolTableRow)
            typeInfoByName[result.typeName] = result.typeInfo
        }

        mutating func setMethodDescriptorMemberSymbols(for result: ProcessMemberSymbolResult) {
            methodDescriptorMemberSymbolRowsByKind[result.memberKind, default: [:]][result.typeName, default: [:]][result.typeNodeIndex, default: []].append(result.symbolTableRow)
            typeInfoByName[result.typeName] = result.typeInfo
        }

        mutating func setProtocolWitnessMemberSymbols(for result: ProcessMemberSymbolResult) {
            protocolWitnessMemberSymbolRowsByKind[result.memberKind, default: [:]][result.typeName, default: [:]][result.typeNodeIndex, default: []].append(result.symbolTableRow)
            typeInfoByName[result.typeName] = result.typeInfo
        }

        mutating func setGlobalSymbols(for result: ProcessGlobalSymbolResult) {
            globalSymbolRowsByKind[result.kind, default: []].append(result.symbolTableRow)
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
        var symbolTable: [Symbol] = []
        var tableRowByName: [String: UInt32] = [:]
        var symbolRowsByOffset: OrderedDictionary<Int, [UInt32]> = [:]

        // Raw and cache-adjusted offset keys share one canonical row; a
        // duplicate name updates the existing row in place (last-wins, like
        // the former name-keyed collection pass).
        func canonicalRow(for canonicalSymbol: Symbol) -> UInt32 {
            if let existingRow = tableRowByName[canonicalSymbol.name] {
                symbolTable[Int(existingRow)] = canonicalSymbol
                return existingRow
            }
            let newRow = UInt32(symbolTable.count)
            symbolTable.append(canonicalSymbol)
            tableRowByName[canonicalSymbol.name] = newRow
            return newRow
        }

        for symbol in machO.symbols where symbol.name.isSwiftSymbol && !symbol.nlist.isExternal {
            let rawOffset = symbol.offset
            var canonicalOffset = rawOffset
            var hasAdjustedOffset = false
            if let cache = machO.cache, rawOffset >= 0, machO is MachOFile {
                canonicalOffset = rawOffset - cache.mainCacheHeader.sharedRegionStart.cast()
                hasAdjustedOffset = true
            }
            let row = canonicalRow(for: .init(offset: canonicalOffset, name: symbol.name, isExternal: symbol.nlist.isExternal))
            symbolRowsByOffset[rawOffset, default: []].append(row)
            if hasAdjustedOffset {
                symbolRowsByOffset[canonicalOffset, default: []].append(row)
            }
        }

        for exportedSymbol in machO.exportedSymbols where exportedSymbol.name.isSwiftSymbol {
            if let rawOffset = exportedSymbol.offset, tableRowByName[exportedSymbol.name] == nil {
                var canonicalOffset = rawOffset
                if machO is MachOFile {
                    canonicalOffset += machO.startOffset
                }
                let row = canonicalRow(for: .init(offset: canonicalOffset, name: exportedSymbol.name))
                symbolRowsByOffset[rawOffset, default: []].append(row)
                symbolRowsByOffset[canonicalOffset, default: []].append(row)
            }
        }

        // Single sequential sweep: demangle each symbol cache-free onto a
        // transient tree, classify on that tree, and intern the result into
        // the arena builder. Nothing touches the global `NodeCache` and no
        // class trees outlive the loop iteration (NodeStore migration plan,
        // Stage 1). Indexes accumulate directly in their final row-index
        // form (Stage 3), so `freeze()` is followed by a plain move into
        // `Storage`, not a conversion pass.
        let totalSymbolCount = symbolTable.count

        var builder = NodeStoreBuilder()
        var rootNodeIndexByTableRow = [NodeStore.NodeIndex?](repeating: nil, count: totalSymbolCount)
        var rowIndexes = RowIndexes()

        for row in 0..<totalSymbolCount {
            if row % 500 == 0 {
                progressContinuation?.yield(Progress(currentCount: row, totalCount: totalSymbolCount))
            }

            let symbol = symbolTable[row]
            guard let rootNode = try? demangleAsNodeTransient(symbol.name) else { continue }
            let symbolTableRow = UInt32(row)
            rootNodeIndexByTableRow[row] = builder.intern(rootNode)

            guard rootNode.isKind(of: .global), let node = rootNode.children.first else { continue }

            rowIndexes.appendSymbolRow(symbolTableRow, for: node.kind)

            if node.kind == .objCAttribute || node.kind == .nonObjCAttribute {
                if let extracted = processThunkAttributeSymbol(thunkKind: node.kind, rootNode: rootNode) {
                    rowIndexes.appendThunkAttributeMember(extracted.member, forKind: node.kind, typeName: extracted.typeName)
                }
                continue
            }

            if rootNode.isGlobal {
                if !symbol.isExternal {
                    if let result = processGlobalSymbol(symbolTableRow, node: node) {
                        rowIndexes.setGlobalSymbols(for: result)
                    }
                }
            } else {
                if node.kind == .methodDescriptor, let firstChild = node.children.first {
                    if let result = processMemberSymbol(symbolTableRow, node: firstChild, builder: &builder) {
                        rowIndexes.setMethodDescriptorMemberSymbols(for: result)
                    }
                } else if node.kind == .protocolWitness, let firstChild = node.children.first {
                    if let result = processMemberSymbol(symbolTableRow, node: firstChild, builder: &builder) {
                        rowIndexes.setProtocolWitnessMemberSymbols(for: result)
                    }
                } else if node.kind == .mergedFunction, let secondChild = rootNode.children.second {
                    if let result = processMemberSymbol(symbolTableRow, node: secondChild, builder: &builder) {
                        rowIndexes.setMemberSymbols(for: result)
                    }
                } else if node.kind == .opaqueTypeDescriptor, let firstChild = node.children.first, firstChild.kind == .opaqueReturnTypeOf, let memberSymbol = firstChild.children.first {
                    if symbol.offset > 0 {
                        rowIndexes.opaqueTypeDescriptorSymbolRowByNodeIndex[builder.intern(memberSymbol)] = symbolTableRow
                    }
                } else {
                    if let result = processMemberSymbol(symbolTableRow, node: node, builder: &builder) {
                        rowIndexes.setMemberSymbols(for: result)
                    }
                }
            }
        }
        progressContinuation?.yield(Progress(currentCount: totalSymbolCount, totalCount: totalSymbolCount))

        return Storage(
            nodeStore: builder.freeze(),
            symbolTable: symbolTable,
            rootNodeIndexByTableRow: rootNodeIndexByTableRow,
            tableRowByName: tableRowByName,
            symbolRowsByOffset: symbolRowsByOffset,
            rowIndexes: rowIndexes
        )
    }

    fileprivate struct ProcessMemberSymbolResult: Sendable {
        let memberKind: MemberKind
        let typeName: String
        let typeNodeIndex: NodeStore.NodeIndex
        let typeInfo: TypeInfo
        let symbolTableRow: UInt32
    }

    private func processMemberSymbol(_ symbolTableRow: UInt32, node: Node, builder: inout NodeStoreBuilder) -> ProcessMemberSymbolResult? {
        if node.kind == .static, let firstChild = node.children.first, firstChild.kind.isMember {
            return processMemberSymbol(symbolTableRow, node: firstChild, traits: [.isStatic], builder: &builder)
        } else if node.kind.isMember {
            return processMemberSymbol(symbolTableRow, node: node, traits: [], builder: &builder)
        }
        return nil
    }

    private func processMemberSymbol(_ symbolTableRow: UInt32, node: Node, traits: MemberKind.Traits, builder: inout NodeStoreBuilder) -> ProcessMemberSymbolResult? {
        var traits = traits
        let node = node
        switch node.kind {
        case .allocator:
            guard var first = node.children.first else { return nil }
            if first.kind == .extension, let type = first.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            return processMemberSymbol(symbolTableRow, node: first, memberKind: .allocator(inExtension: traits.contains(.inExtension)), builder: &builder)
        case .deallocator:
            guard let first = node.children.first else { return nil }
            return processMemberSymbol(symbolTableRow, node: first, memberKind: .deallocator, builder: &builder)
        case .constructor:
            guard var first = node.children.first else { return nil }
            if first.kind == .extension, let type = first.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            return processMemberSymbol(symbolTableRow, node: first, memberKind: .constructor(inExtension: traits.contains(.inExtension)), builder: &builder)
        case .destructor:
            guard let first = node.children.first else { return nil }
            return processMemberSymbol(symbolTableRow, node: first, memberKind: .destructor, builder: &builder)
        case .function:
            guard var first = node.children.first else { return nil }
            if first.kind == .extension, let type = first.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            return processMemberSymbol(symbolTableRow, node: first, memberKind: .function(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic)), builder: &builder)
        case .variable:
            // Stored variable reached directly (not through getter/setter)
            traits.insert(.isStorage)
            var first = node.children.first
            if first?.kind == .extension, let type = first?.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            if let first {
                return processMemberSymbol(symbolTableRow, node: first, memberKind: .variable(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic), isStorage: traits.contains(.isStorage)), builder: &builder)
            }
        case .getter,
             .setter:
            if let variableNode = node.children.first, variableNode.kind == .variable, var first = variableNode.children.first {
                if first.kind == .extension, let type = first.children.at(1) {
                    traits.insert(.inExtension)
                    first = type
                }
                return processMemberSymbol(symbolTableRow, node: first, memberKind: .variable(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic), isStorage: traits.contains(.isStorage)), builder: &builder)
            } else if let subscriptNode = node.children.first, subscriptNode.kind == .subscript, var first = subscriptNode.children.first {
                if first.kind == .extension, let type = first.children.at(1) {
                    traits.insert(.inExtension)
                    first = type
                }
                return processMemberSymbol(symbolTableRow, node: first, memberKind: .subscript(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic)), builder: &builder)
            }
        default:
            break
        }
        return nil
    }

    private func processMemberSymbol(_ symbolTableRow: UInt32, node: Node, memberKind: MemberKind, builder: inout NodeStoreBuilder) -> ProcessMemberSymbolResult? {
        if let typeKind = node.kind.typeKind {
            // The transient `.type` wrapper exists only for printing; the
            // arena-resident wrapper is built directly from the interned
            // context node's index, so no class tree survives this call.
            let typeName = Node.create(kind: .type, child: node).print(using: .interfaceTypeBuilderOnly)
            let typeNodeIndex = builder.intern(kind: .type, children: [builder.intern(node)])
            return .init(memberKind: memberKind, typeName: typeName, typeNodeIndex: typeNodeIndex, typeInfo: .init(name: typeName, kind: typeKind), symbolTableRow: symbolTableRow)
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
        let symbolTableRow: UInt32
    }

    private func processGlobalSymbol(_ symbolTableRow: UInt32, node: Node) -> ProcessGlobalSymbolResult? {
        switch node.kind {
        case .function:
            return .init(kind: .function, symbolTableRow: symbolTableRow)
        case .variable:
            // When we reach .variable directly (not through getter/setter),
            // this is a stored variable declaration
            return .init(kind: .variable(isStorage: true), symbolTableRow: symbolTableRow)
        case .getter,
             .setter:
            if let variableNode = node.children.first, variableNode.kind == .variable {
                return processGlobalSymbol(symbolTableRow, node: variableNode)
            }
        default:
            break
        }
        return nil
    }

    public func allSymbols<MachO: MachORepresentableWithCache>(in machO: MachO) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return storage.symbolRowsByKind.values.flatMap { storage.demangledSymbols(atRows: $0) }
    }

    public func symbolsByKind<MachO: MachORepresentableWithCache>(in machO: MachO) -> OrderedDictionary<Node.Kind, [DemangledSymbol]> {
        guard let storage = storage(in: machO) else { return [:] }
        return storage.symbolRowsByKind.mapValues { storage.demangledSymbols(atRows: $0) }
    }

    public func typeInfo<MachO: MachORepresentableWithCache>(for name: String, in machO: MachO) -> TypeInfo? {
        return storage(in: machO)?.typeInfoByName[name]
    }

    public func symbols<MachO: MachORepresentableWithCache>(of kinds: Node.Kind..., in machO: MachO) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { storage.demangledSymbols(atRows: storage.symbolRowsByKind[$0] ?? []) }.reduce(into: []) { $0 += $1 }
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
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let memberRows = storage.memberSymbolRowsByKind[kind] else { return [] }
            return memberRows.values.flatMap { rowsByTypeNodeIndex in
                rowsByTypeNodeIndex.values.flatMap { storage.demangledSymbols(atRows: $0) }
            }
        }.reduce(into: []) { $0 += $1 }
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, in machO: MachO) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.memberSymbolRowsByKind[kind]?[name] else { return [] }
            return rowsByTypeNodeIndex.values.flatMap { storage.demangledSymbols(atRows: $0) }
        }.reduce(into: []) { $0 += $1 }
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, node: Node, in machO: MachO) -> [DemangledSymbol] {
        // Callers hold an externally demangled `Node` (MetadataReader context
        // demangling), while keys are node indexes into the frozen store.
        // The type-name bucket holds at most a handful of type nodes, so a
        // structural walk per key is cheap.
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.memberSymbolRowsByKind[kind]?[name] else { return [] }
            guard let matched = rowsByTypeNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) }) else { return [] }
            return storage.demangledSymbols(atRows: matched.value)
        }.reduce(into: []) { $0 += $1 }
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, node: NodeReference, in machO: MachO) -> [DemangledSymbol] {
        // Same lookup as the `Node` overload, for callers holding a
        // store-backed reference — possibly minted into a different store
        // than the index's own (for example a `TypeName` mini store):
        // same-store keys match in O(1) via index equality, cross-store
        // keys by a structural walk over the handful of bucket entries.
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.memberSymbolRowsByKind[kind]?[name] else { return [] }
            guard let matched = rowsByTypeNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) }) else { return [] }
            return storage.demangledSymbols(atRows: matched.value)
        }.reduce(into: []) { $0 += $1 }
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., excluding names: borrowing Set<String>, in machO: MachO) -> OrderedDictionary<NodeReference, OrderedDictionary<MemberKind, [DemangledSymbol]>> {
        guard let storage = storage(in: machO) else { return [:] }
        var result: OrderedDictionary<NodeReference, OrderedDictionary<MemberKind, [DemangledSymbol]>> = [:]
        for kind in kinds {
            guard let memberRows = storage.memberSymbolRowsByKind[kind] else { continue }
            for (typeName, rowsByTypeNodeIndex) in memberRows where !names.contains(typeName) {
                for (typeNodeIndex, rows) in rowsByTypeNodeIndex {
                    result[storage.nodeStore.reference(at: typeNodeIndex), default: [:]][kind, default: []].append(contentsOf: storage.demangledSymbols(atRows: rows))
                }
            }
        }
        return result
    }

    public func methodDescriptorMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., in machO: MachO) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let memberRows = storage.methodDescriptorMemberSymbolRowsByKind[kind] else { return [] }
            return memberRows.values.flatMap { rowsByTypeNodeIndex in
                rowsByTypeNodeIndex.values.flatMap { storage.demangledSymbols(atRows: $0) }
            }
        }.reduce(into: []) { $0 += $1 }
    }

    public func methodDescriptorMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, in machO: MachO) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.methodDescriptorMemberSymbolRowsByKind[kind]?[name] else { return [] }
            return rowsByTypeNodeIndex.values.flatMap { storage.demangledSymbols(atRows: $0) }
        }.reduce(into: []) { $0 += $1 }
    }

    public func protocolWitnessMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., in machO: MachO) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let memberRows = storage.protocolWitnessMemberSymbolRowsByKind[kind] else { return [] }
            return memberRows.values.flatMap { rowsByTypeNodeIndex in
                rowsByTypeNodeIndex.values.flatMap { storage.demangledSymbols(atRows: $0) }
            }
        }.reduce(into: []) { $0 += $1 }
    }

    public func protocolWitnessMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, in machO: MachO) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.protocolWitnessMemberSymbolRowsByKind[kind]?[name] else { return [] }
            return rowsByTypeNodeIndex.values.flatMap { storage.demangledSymbols(atRows: $0) }
        }.reduce(into: []) { $0 += $1 }
    }

    public func globalSymbols<MachO: MachORepresentableWithCache>(of kinds: GlobalKind..., in machO: MachO) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { storage.demangledSymbols(atRows: storage.globalSymbolRowsByKind[$0] ?? []) }.reduce(into: []) { $0 += $1 }
    }

    public func allOpaqueTypeDescriptorSymbols<MachO: MachORepresentableWithCache>(in machO: MachO) -> OrderedDictionary<NodeReference, DemangledSymbol>? {
        guard let storage = storage(in: machO) else { return nil }
        var result: OrderedDictionary<NodeReference, DemangledSymbol> = [:]
        for (nodeIndex, row) in storage.opaqueTypeDescriptorSymbolRowByNodeIndex {
            guard let demangledSymbol = storage.demangledSymbol(atRow: row) else { continue }
            result[storage.nodeStore.reference(at: nodeIndex)] = demangledSymbol
        }
        return result
    }

    public func opaqueTypeDescriptorSymbol<MachO: MachORepresentableWithCache>(for node: Node, in machO: MachO) -> DemangledSymbol? {
        // The caller's `node` was demangled during printing; keys live in the
        // frozen store. Structural comparison early-outs on the first
        // mismatching kind, so the linear scan stays cheap relative to the
        // printing work that triggers it.
        guard let storage = storage(in: machO) else { return nil }
        guard let matched = storage.opaqueTypeDescriptorSymbolRowByNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) }) else { return nil }
        return storage.demangledSymbol(atRow: matched.value)
    }

    package func symbols<MachO: MachORepresentableWithCache>(for offset: Int, in machO: MachO) -> Symbols? {
        guard let storage = storage(in: machO), let rows = storage.symbolRowsByOffset[offset], !rows.isEmpty else { return nil }
        return .init(offset: offset, symbols: rows.map { storage.symbol(atRow: $0, offset: offset) })
    }

    /// Store-backed handle for a symbol's demangled tree. Hits the frozen
    /// image store for symbols covered by the build sweep; symbols outside
    /// the sweep are demangled cache-free into a per-symbol mini store, so
    /// every caller receives a uniform `NodeReference`.
    package func demangledNodeReference<MachO: MachORepresentableWithCache>(for symbol: Symbol, in machO: MachO) -> NodeReference? {
        guard let cacheStorage = storage(in: machO) else { return nil }
        if let row = cacheStorage.tableRowByName[symbol.name],
           cacheStorage.symbolTable[Int(row)].offset == symbol.offset,
           let rootNodeIndex = cacheStorage.rootNodeIndexByTableRow[Int(row)] {
            return cacheStorage.nodeStore.reference(at: rootNodeIndex)
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

extension NlistProtocol {
    package var isExternal: Bool {
        guard let flags = flags, let type = flags.type else { return false }
        return flags.contains(.ext) && type == .undf
    }
}
