import Foundation
import FoundationToolbox
import MachOKit
import MachOKitExtensions
import MachOResolving
@_spi(Internals) import Demangling
import OrderedCollections
import Utilities
import Dependencies
@_spi(Internals) import MachOCaches
@_spi(Internals) import MachOSymbols

@_spi(ForSymbolViewer)
@_spi(Internals)
public final class SwiftSymbolIndexStore: @unchecked Sendable {
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

        public static let allCases: [SwiftSymbolIndexStore.MemberKind] = [
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

        public static let allCases: [SwiftSymbolIndexStore.GlobalKind] = [
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
        public enum Kind: Equatable, Sendable {
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

    /// What a symbol at an address it shares with others belongs to — how
    /// the one a caller is after is told apart from the names identical
    /// code folding put beside it.
    public enum SymbolOwnerKind: Hashable, Sendable {
        /// The type its first protocol conformance names: a protocol
        /// witness's conforming type.
        case conformingType
        /// Its first protocol: a protocol requirement's, or a default
        /// implementation's.
        case `protocol`
    }

    public final class Storage: @unchecked Sendable {
        typealias MemberSymbolRows = OrderedDictionary<String, OrderedDictionary<NodeStore.NodeIndex, SymbolRowBucket>>

        /// Flat symbol table (Stage 3, offset-ized by evolution proposal
        /// 0001): one 16-byte row per unique symbol name, holding the
        /// canonical (cache-adjusted) offset plus a packed reference into
        /// the table's name source — the image's mmap'd string table for
        /// `MachOImage` rows, the table's private byte buffer otherwise.
        /// No name `String` is retained; vend paths materialize names on
        /// demand. Every index below stores 4-byte row indices into this
        /// table, and vended `DemangledSymbol` values share it. Name → row
        /// lookup is `symbolTable.row(forName:)`, a byte-level binary
        /// search over the table's name-order permutation (the former
        /// `tableRowByName` dictionary is build-time-only now).
        let symbolTable: SymbolTable

        /// Plain `Dictionary`: the only consumer is the keyed lookup in
        /// `symbols(for:in:)` — nothing iterates it in order (proposal 0001
        /// rider; the former `OrderedDictionary` paid an ordering table for
        /// hundreds of thousands of entries nobody read). Values are
        /// `SymbolRowBucket` (proposal 0003): the dominant single-row case
        /// stays inline in the dictionary slot instead of paying a per-key
        /// array allocation.
        let symbolRowsByOffset: [Int: SymbolRowBucket]

        /// Export-trie facts for the image (evolution proposal 0008), the
        /// backing for `isExported(name:)`, collected by MachOKitExtensions'
        /// symbol sweep along with the table.
        let exportFacts: SymbolExportFacts

        /// Whether the symbol table holds any local Swift symbol — one whose
        /// `N_EXT` bit is clear (evolution proposal
        /// `evolution-unobservable-presence`). `false` for an image stripped
        /// of its local symbols — SwiftUI in the macOS 13.0–14.8 dyld shared
        /// caches — which keeps only its exported Swift names. A debug-map
        /// entry only reserves a row and does not count; a name refused by
        /// the packed-reference budget still does, since the symbol is there.
        let hasLocalSwiftSymbols: Bool

        /// The image's symbolic-mangling symbols (`_symbolic ` /
        /// `_default assoc type `), collected by the same symtab pass into a
        /// table of their own (evolution proposal
        /// `symbolic-mangling-symbol-index`). Listed in no index above —
        /// `symbolRowsByOffset` least of all: its callers expect names that
        /// demangle, and these never do.
        let symbolicManglingSymbolTable: SymbolTable

        /// Whether `name` has an export-trie entry in this image:
        /// `true`/`false` per the trie, or `nil` when the image carries no
        /// export information at all (see `SymbolExportFacts.hasExportInformation`).
        /// Only Swift names are recorded, matching the table's population —
        /// callers query with mangled member-symbol names.
        func isExported(name: String) -> Bool? {
            exportFacts.isExported(name: name, in: symbolTable)
        }

        /// Symbols demangled after the store was frozen (rare path: lookups
        /// for names that were not part of the build sweep). The frozen main
        /// arena cannot grow, so late names go into this appendable per-image
        /// side store; every consumer keeps receiving a uniform
        /// `NodeReference`. Deliberately self-held rather than shared with
        /// `InternedNodeReferenceCache`'s image store: that cache is evicted
        /// and rebuilt under memory pressure while this `Storage` is not, and
        /// sharing would leave the two referencing different stores after an
        /// eviction.
        private let lateNameStore = SharedNodeStore()

        /// Verdict cache over `lateNameStore`, keyed by name like the
        /// symbol table's own row lookup: a demangled tree is a pure
        /// function of the symbol name, so two symbols at different offsets
        /// sharing a name share a tree. A stored `nil` records a name the demangler
        /// rejected — rejection is exactly as deterministic as success, so
        /// it is cached the same way and never retried (`SharedNodeStore`
        /// itself throws on failure and caches nothing).
        @Mutex
        private var lateDemangledNodeByName: [String: NodeReference?] = [:]

        /// Builds the demangled index from the symbol table, reporting
        /// progress to the continuation when one is given.
        typealias DemangledIndexBuilder = @Sendable (SymbolTable, AsyncStream<Progress>.Continuation?) -> DemangledIndex

        private let demangledIndexBuilder: DemangledIndexBuilder

        /// Held while the demangled index is built, so concurrent first
        /// readers wait for the one build instead of each running their own.
        private let demangledIndexBuildLock = NSLock()

        @Mutex
        private var builtDemangledIndex: DemangledIndex?

        fileprivate init(
            symbolTable: SymbolTable,
            symbolRowsByOffset: [Int: SymbolRowBucket],
            exportFacts: SymbolExportFacts,
            hasLocalSwiftSymbols: Bool,
            symbolicManglingSymbolTable: SymbolTable,
            demangledIndexBuilder: @escaping DemangledIndexBuilder
        ) {
            self.symbolTable = symbolTable
            self.symbolRowsByOffset = symbolRowsByOffset
            self.exportFacts = exportFacts
            self.hasLocalSwiftSymbols = hasLocalSwiftSymbols
            self.symbolicManglingSymbolTable = symbolicManglingSymbolTable
            self.demangledIndexBuilder = demangledIndexBuilder
        }

        /// The demangled index, built on first use.
        var demangledIndex: DemangledIndex {
            demangledIndex(reportingProgressTo: nil)
        }

        /// The demangled index, built on first use with its progress reported
        /// to `progressContinuation`; a caller that finds it built gets no
        /// progress.
        ///
        /// The build demangles every name, so it runs on a large stack taken
        /// before the build lock: a demangle that hopped threads while the
        /// lock is held would leave every other reader waiting behind the hop.
        func demangledIndex(reportingProgressTo progressContinuation: AsyncStream<Progress>.Continuation?) -> DemangledIndex {
            if let builtDemangledIndex = _builtDemangledIndex.withLockUnchecked({ $0 }) {
                return builtDemangledIndex
            }
            return StackSafeExecutor.withLargeStack { [self] in
                demangledIndexBuildLock.lock()
                defer { demangledIndexBuildLock.unlock() }
                if let builtDemangledIndex = _builtDemangledIndex.withLockUnchecked({ $0 }) {
                    return builtDemangledIndex
                }
                let demangledIndex = demangledIndexBuilder(symbolTable, progressContinuation)
                _builtDemangledIndex.withLockUnchecked { $0 = demangledIndex }
                return demangledIndex
            }
        }

        /// Whether the demangled index has been built.
        var hasBuiltDemangledIndex: Bool {
            _builtDemangledIndex.withLockUnchecked { $0 != nil }
        }

        // MARK: Demangled index fields

        var nodeStore: NodeStore { demangledIndex.nodeStore }

        var rootNodeIndexByTableRow: [NodeStore.NodeIndex?] { demangledIndex.rootNodeIndexByTableRow }

        var typeInfoByName: [String: OrderedDictionary<NodeStore.NodeIndex, TypeInfo>] { demangledIndex.typeInfoByName }

        var globalSymbolRowsByKind: OrderedDictionary<GlobalKind, [UInt32]> { demangledIndex.globalSymbolRowsByKind }

        var opaqueTypeDescriptorSymbolRowByNodeIndex: OrderedDictionary<NodeStore.NodeIndex, UInt32> { demangledIndex.opaqueTypeDescriptorSymbolRowByNodeIndex }

        var opaqueTypeDescriptorSymbolRowByMemberNode: [StructuralNodeReferenceKey: UInt32] { demangledIndex.opaqueTypeDescriptorSymbolRowByMemberNode }

        var memberSymbolRowsByKind: OrderedDictionary<MemberKind, MemberSymbolRows> { demangledIndex.memberSymbolRowsByKind }

        var methodDescriptorMemberSymbolRowsByKind: OrderedDictionary<MemberKind, MemberSymbolRows> { demangledIndex.methodDescriptorMemberSymbolRowsByKind }

        var protocolWitnessMemberSymbolRowsByKind: OrderedDictionary<MemberKind, MemberSymbolRows> { demangledIndex.protocolWitnessMemberSymbolRowsByKind }

        var objcThunkMemberSymbolRowsByKind: OrderedDictionary<MemberKind, MemberSymbolRows> { demangledIndex.objcThunkMemberSymbolRowsByKind }

        var specializedInitializerSymbolRowsByKind: OrderedDictionary<MemberKind, MemberSymbolRows> { demangledIndex.specializedInitializerSymbolRowsByKind }

        var symbolRowsByKind: OrderedDictionary<Node.Kind, [UInt32]> { demangledIndex.symbolRowsByKind }

        var thunkAttributeMembersByKindAndTypeName: [Node.Kind: [String: OrderedDictionary<NodeStore.NodeIndex, [ThunkAttributeMember]>]] { demangledIndex.thunkAttributeMembersByKindAndTypeName }

        /// What the build sweep's second pass derives from the symbol table:
        /// every row's demangled tree and the indexes classified on it.
        ///
        /// Built on the first query that needs it (evolution proposal
        /// `machofile-performance`). A symbol lookup by offset, the
        /// symbolic-mangling table and the export facts read the table alone,
        /// and an image read only for another's sake — a dependency whose
        /// private type the layout engine names through the descriptor's
        /// symbol — never needs its hundreds of thousands of names demangled:
        /// laying out SwiftUI demangled the whole of every dependency it named
        /// a type in, 7.7 of 27.8 seconds.
        final class DemangledIndex: @unchecked Sendable {
            /// The frozen arena holding every demangled node of this image.
            /// All `NodeReference` values vended by this storage point into it.
            let nodeStore: NodeStore

            /// Parallel to `symbolTable`: the row's demangled root node, or
            /// `nil` for names the demangler rejected (those still occupy a row
            /// because `symbolRowsByOffset` references them).
            let rootNodeIndexByTableRow: [NodeStore.NodeIndex?]

            /// Per printed type name, the `TypeInfo` of every distinct context
            /// node that printed to it. The stripped interface print is not
            /// injective — same-named private types from different files collide
            /// on it (issue #115) — so the name alone cannot key a single
            /// `TypeInfo`; the interned context node disambiguates.
            let typeInfoByName: [String: OrderedDictionary<NodeStore.NodeIndex, TypeInfo>]

            let globalSymbolRowsByKind: OrderedDictionary<GlobalKind, [UInt32]>

            let opaqueTypeDescriptorSymbolRowByNodeIndex: OrderedDictionary<NodeStore.NodeIndex, UInt32>

            /// The same entries as `opaqueTypeDescriptorSymbolRowByNodeIndex`,
            /// keyed **structurally** so a print-time query is one hash probe.
            ///
            /// `opaqueTypeDescriptorSymbol(for:)` is queried with a node the caller
            /// demangled while printing — a different store — so node-index
            /// equality cannot answer it. Bucketing by `DemanglingNode.identifier`
            /// and scanning the bucket was the first attempt at narrowing that, on
            /// the assumption that a member identifier picks out "normally exactly
            /// one" descriptor. It does not: in SwiftUI the `body` bucket alone
            /// holds hundreds of entries (every `some View` implementation shares
            /// the identifier), and the caller queries once per printed
            /// `some`-returning declaration with no memoization, so the scan was
            /// quadratic in a count that runs into the thousands — and each
            /// `structurallyEquals` allocates a fresh visited-pair set before its
            /// first kind check.
            ///
            /// `StructuralNodeReferenceKey` hashes a stored `NodeReference` and a
            /// queried `Node` alike, which is what makes the direct dictionary
            /// possible.
            let opaqueTypeDescriptorSymbolRowByMemberNode: [StructuralNodeReferenceKey: UInt32]

            let memberSymbolRowsByKind: OrderedDictionary<MemberKind, MemberSymbolRows>

            let methodDescriptorMemberSymbolRowsByKind: OrderedDictionary<MemberKind, MemberSymbolRows>

            let protocolWitnessMemberSymbolRowsByKind: OrderedDictionary<MemberKind, MemberSymbolRows>

            /// The members an `@objc` thunk (`$s…To`) enters, bucketed like the
            /// three member indexes above but holding the THUNK's row. A thunk is
            /// not a member symbol and the member index never files it; this
            /// index exists for the members whose Swift entry point the optimizer
            /// inlined into the thunk and removed, which leaves the thunk as the
            /// only symbol the image has for them (evolution proposal
            /// `thunk-only-objc-members`).
            let objcThunkMemberSymbolRowsByKind: OrderedDictionary<MemberKind, MemberSymbolRows>

            /// The initializers a function signature specialization of the
            /// initializing entry point (`$s…fcTf…`) specializes, bucketed like
            /// the member indexes above but holding the SPECIALIZATION's row,
            /// always under `constructor`. A specialization is not a member
            /// symbol and the member index never files it; this index exists
            /// for the initializers whose allocating entry point the optimizer
            /// inlined into the callers and whose initializing entry point it
            /// replaced by the specialization and removed, which leaves the
            /// specialization as the only code the initializer has — the shape
            /// Swift 6.4's whole-module optimization gives an internal class's
            /// initializer. Specializations of anything else are not filed.
            let specializedInitializerSymbolRowsByKind: OrderedDictionary<MemberKind, MemberSymbolRows>

            let symbolRowsByKind: OrderedDictionary<Node.Kind, [UInt32]>

            /// Like the member indexes, bucketed by printed type name first and
            /// the interned parent-context node second, so same-named private
            /// types' thunk attributes never cross-stamp each other's members.
            let thunkAttributeMembersByKindAndTypeName: [Node.Kind: [String: OrderedDictionary<NodeStore.NodeIndex, [ThunkAttributeMember]>]]

            fileprivate init(
                nodeStore: NodeStore,
                rootNodeIndexByTableRow: [NodeStore.NodeIndex?],
                rowIndexes: consuming RowIndexes
            ) {
                self.nodeStore = nodeStore
                self.rootNodeIndexByTableRow = rootNodeIndexByTableRow
                self.typeInfoByName = rowIndexes.typeInfoByName
                self.globalSymbolRowsByKind = rowIndexes.globalSymbolRowsByKind
                self.opaqueTypeDescriptorSymbolRowByNodeIndex = rowIndexes.opaqueTypeDescriptorSymbolRowByNodeIndex
                var opaqueTypeDescriptorSymbolRowByMemberNode: [StructuralNodeReferenceKey: UInt32] = [:]
                opaqueTypeDescriptorSymbolRowByMemberNode.reserveCapacity(rowIndexes.opaqueTypeDescriptorSymbolRowByNodeIndex.count)
                for (memberNodeIndex, symbolTableRow) in rowIndexes.opaqueTypeDescriptorSymbolRowByNodeIndex {
                    // First wins, matching the ordered dictionary this replaced:
                    // its per-node-index keys were already unique, so a collision
                    // here means two arena nodes that are structurally equal, and
                    // either answers the query identically.
                    let memberNodeKey = StructuralNodeReferenceKey(nodeStore.reference(at: memberNodeIndex))
                    if opaqueTypeDescriptorSymbolRowByMemberNode[memberNodeKey] == nil {
                        opaqueTypeDescriptorSymbolRowByMemberNode[memberNodeKey] = symbolTableRow
                    }
                }
                self.opaqueTypeDescriptorSymbolRowByMemberNode = opaqueTypeDescriptorSymbolRowByMemberNode
                self.memberSymbolRowsByKind = rowIndexes.memberSymbolRowsByKind
                self.methodDescriptorMemberSymbolRowsByKind = rowIndexes.methodDescriptorMemberSymbolRowsByKind
                self.protocolWitnessMemberSymbolRowsByKind = rowIndexes.protocolWitnessMemberSymbolRowsByKind
                self.objcThunkMemberSymbolRowsByKind = rowIndexes.objcThunkMemberSymbolRowsByKind
                self.specializedInitializerSymbolRowsByKind = rowIndexes.specializedInitializerSymbolRowsByKind
                self.symbolRowsByKind = rowIndexes.symbolRowsByKind
                self.thunkAttributeMembersByKindAndTypeName = rowIndexes.thunkAttributeMembersByKindAndTypeName
            }
        }

        /// Get-or-demangle for a name outside the build sweep.
        ///
        /// The demangle runs *outside* the critical section: it can hop to a
        /// large-stack thread and block on a semaphore, and an
        /// `os_unfair_lock` must not be held across a blocking wait (priority
        /// donation is lost and every other late lookup on the image
        /// serializes behind it). Two threads missing concurrently both
        /// demangle, but both intern into the one `lateNameStore`, whose
        /// structural dedup hands them the *same* reference — the race costs
        /// a duplicate parse, never references into different stores. The
        /// insert-if-absent shape stays only to keep one canonical verdict
        /// per name.
        ///
        /// Rejections are cached like successes (`nil` verdict): the
        /// demangler is deterministic, so a retry can only re-pay the failed
        /// demangle. Sweep-covered names never reach this path at all —
        /// `demangledNodeReference(for:in:)` answers them from the table
        /// verdict — so the population here is genuinely late names only.
        fileprivate func lateDemangledNode(forName name: String) -> NodeReference? {
            if let cachedVerdict = _lateDemangledNodeByName.withLockUnchecked({ $0[name] }) {
                return cachedVerdict
            }
            let demangled = try? lateNameStore.demangle(name)
            return _lateDemangledNodeByName.withLockUnchecked { cache in
                if let winner = cache[name] { return winner }
                // `updateValue` rather than the subscript: assigning an
                // `Optional` value through the subscript of an
                // optional-valued dictionary is exactly the shape where a
                // `nil` silently means "remove the key" instead of "store
                // the rejection verdict".
                cache.updateValue(demangled, forKey: name)
                return demangled
            }
        }

        /// Test-only visibility into the late cache: `.some(.some)` is a
        /// cached success, `.some(.none)` a cached rejection, `.none` a name
        /// never attempted. Production code goes through
        /// `lateDemangledNode(forName:)`.
        func lateDemangleVerdictForTesting(forName name: String) -> NodeReference?? {
            _lateDemangledNodeByName.withLockUnchecked { $0[name] }
        }

        // MARK: Symbols grouped by owner

        /// One grouping of an offset's rows: the offset, the rule naming each
        /// row's owner, and the options the owner is printed with.
        struct OwnerGroupingKey: Hashable {
            let offset: Int
            let ownerKind: SymbolOwnerKind
            let printOptionsRawValue: Int
        }

        /// Per queried offset, owner rule and print options, the rows there
        /// grouped by the name of their owner, each group in the offset's row
        /// order — built the first time the offset is asked about that way
        /// (evolution proposal `faster-lazy-definition-indexing`).
        ///
        /// Identical code folding piles the witnesses of many conformances
        /// onto one address: in SwiftUI a single `_destroySelf` or value
        /// witness implementation carries well over a thousand names. Every
        /// conformance asks the address for its own witness, and answering
        /// that by demangling, searching and printing each name in turn was
        /// quadratic in the group's size — 3.65 million checks over 17,852
        /// distinct names for SwiftUI alone. Grouping once makes each later
        /// question two dictionary probes.
        @Mutex
        private var rowsByOwnerNameByGroupingKey: [OwnerGroupingKey: [String: [UInt32]]] = [:]

        /// The rows at `offset` whose owner, named by `ownerKind` and printed
        /// with `options`, prints as `ownerName`, in the order
        /// `symbolRowsByOffset` lists them.
        ///
        /// The grouping runs outside the lock — it demangles nothing, but it
        /// walks and prints trees, which may hop to a large-stack thread —
        /// and two threads grouping the same offset at once both do the work;
        /// the first to finish is kept, and both answer from the same rows,
        /// since the grouping is a pure function of the frozen table.
        func rows(at offset: Int, ownedBy ownerName: String, ownerKind: SymbolOwnerKind, options: DemangleOptions) -> [UInt32] {
            let groupingKey = OwnerGroupingKey(offset: offset, ownerKind: ownerKind, printOptionsRawValue: options.rawValue)
            if let rowsByOwnerName = _rowsByOwnerNameByGroupingKey.withLockUnchecked({ $0[groupingKey] }) {
                return rowsByOwnerName[ownerName] ?? []
            }
            let rowsByOwnerName = groupRowsByOwnerName(at: offset, ownerKind: ownerKind, options: options)
            return _rowsByOwnerNameByGroupingKey.withLockUnchecked { groupings in
                if let winner = groupings[groupingKey] {
                    return winner[ownerName] ?? []
                }
                groupings[groupingKey] = rowsByOwnerName
                return rowsByOwnerName[ownerName] ?? []
            }
        }

        /// The grouping itself, by the rules the attributing code matched
        /// one symbol at a time before: the conformance is the first
        /// `protocolConformance` node of the symbol's tree in deduped
        /// preorder and its owner the conformance's first child; a protocol
        /// owner is the first `protocol` node. A row the demangler rejected,
        /// or whose tree has no owner, joins no group — it matched nothing
        /// before either.
        private func groupRowsByOwnerName(at offset: Int, ownerKind: SymbolOwnerKind, options: DemangleOptions) -> [String: [UInt32]] {
            guard let rows = symbolRowsByOffset[offset] else { return [:] }
            let demangledIndex = demangledIndex
            var rowsByOwnerName: [String: [UInt32]] = [:]
            for row in rows {
                guard let rootNodeIndex = demangledIndex.rootNodeIndexByTableRow[Int(row)] else { continue }
                let rootNode = demangledIndex.nodeStore.reference(at: rootNodeIndex)
                let ownerNode: NodeReference? = switch ownerKind {
                case .conformingType:
                    rootNode.first(of: .protocolConformance)?.children.first
                case .protocol:
                    rootNode.first(of: .protocol)
                }
                guard let ownerNode else { continue }
                rowsByOwnerName[ownerNode.print(using: options), default: []].append(row)
            }
            return rowsByOwnerName
        }

        /// Test-only visibility into a grouping: `nil` until the offset has
        /// been asked about with that owner rule and those options.
        func rowsByOwnerNameForTesting(at offset: Int, ownerKind: SymbolOwnerKind, options: DemangleOptions) -> [String: [UInt32]]? {
            let groupingKey = OwnerGroupingKey(offset: offset, ownerKind: ownerKind, printOptionsRawValue: options.rawValue)
            return _rowsByOwnerNameByGroupingKey.withLockUnchecked { $0[groupingKey] }
        }

        // MARK: Row materialization

        /// Rebuilds the `Symbol` for an offset-table row using the queried
        /// offset: raw and cache-adjusted keys share one canonical row, so
        /// the row's stored offset is not necessarily the queried one. The
        /// name is materialized fresh from the table's name source.
        fileprivate func symbol(atRow row: UInt32, offset queriedOffset: Int) -> Symbol {
            return Symbol(offset: queriedOffset, name: symbolTable.materializedName(atRow: row), isExternal: symbolTable.isExternal(atRow: row))
        }

        func demangledSymbol(atRow row: UInt32) -> DemangledSymbol? {
            demangledSymbol(atRow: row, in: demangledIndex)
        }

        func demangledSymbols(atRows rows: some Sequence<UInt32>) -> [DemangledSymbol] {
            let demangledIndex = demangledIndex
            return rows.compactMap { demangledSymbol(atRow: $0, in: demangledIndex) }
        }

        private func demangledSymbol(atRow row: UInt32, in demangledIndex: DemangledIndex) -> DemangledSymbol? {
            guard let rootNodeIndex = demangledIndex.rootNodeIndexByTableRow[Int(row)] else { return nil }
            return DemangledSymbol(symbolTable: symbolTable, symbolTableRow: row, demangledNode: demangledIndex.nodeStore.reference(at: rootNodeIndex))
        }

        /// One-shot acceptance statistic for proposal 0003: how many buckets
        /// stay in the inline single-row form, across the offset index and
        /// the three member-index families' leaf buckets. The proposal's
        /// memory estimate assumes single-row dominance, so this is the
        /// number the acceptance evidence pins.
        func bucketFormStatisticsForTesting() -> (singleRowBucketCount: Int, multipleRowBucketCount: Int) {
            var singleRowBucketCount = 0
            var multipleRowBucketCount = 0
            func tally(_ bucket: SymbolRowBucket) {
                switch bucket {
                case .single:
                    singleRowBucketCount += 1
                case .multiple:
                    multipleRowBucketCount += 1
                }
            }
            for bucket in symbolRowsByOffset.values {
                tally(bucket)
            }
            for memberRowsByKind in [memberSymbolRowsByKind, methodDescriptorMemberSymbolRowsByKind, protocolWitnessMemberSymbolRowsByKind] {
                for memberRows in memberRowsByKind.values {
                    for rowsByTypeNodeIndex in memberRows.values {
                        for bucket in rowsByTypeNodeIndex.values {
                            tally(bucket)
                        }
                    }
                }
            }
            return (singleRowBucketCount, multipleRowBucketCount)
        }
    }

    /// Build-time accumulator holding the row-index form of `Storage`'s
    /// classification indexes. `Storage.init` moves these dictionaries in
    /// unchanged — there is no post-freeze conversion pass, so the former
    /// pending→populate double-index transient peak is gone (Stage 3).
    fileprivate struct RowIndexes {
        var typeInfoByName: [String: OrderedDictionary<NodeStore.NodeIndex, TypeInfo>] = [:]
        var globalSymbolRowsByKind: OrderedDictionary<GlobalKind, [UInt32]> = [:]
        var opaqueTypeDescriptorSymbolRowByNodeIndex: OrderedDictionary<NodeStore.NodeIndex, UInt32> = [:]
        var memberSymbolRowsByKind: OrderedDictionary<MemberKind, Storage.MemberSymbolRows> = [:]
        var methodDescriptorMemberSymbolRowsByKind: OrderedDictionary<MemberKind, Storage.MemberSymbolRows> = [:]
        var protocolWitnessMemberSymbolRowsByKind: OrderedDictionary<MemberKind, Storage.MemberSymbolRows> = [:]
        var objcThunkMemberSymbolRowsByKind: OrderedDictionary<MemberKind, Storage.MemberSymbolRows> = [:]
        var specializedInitializerSymbolRowsByKind: OrderedDictionary<MemberKind, Storage.MemberSymbolRows> = [:]
        var symbolRowsByKind: OrderedDictionary<Node.Kind, [UInt32]> = [:]
        var thunkAttributeMembersByKindAndTypeName: [Node.Kind: [String: OrderedDictionary<NodeStore.NodeIndex, [ThunkAttributeMember]>]] = [:]

        mutating func appendSymbolRow(_ symbolTableRow: UInt32, for kind: Node.Kind) {
            symbolRowsByKind[kind, default: []].append(symbolTableRow)
        }

        mutating func setMemberSymbols(for result: ProcessMemberSymbolResult) {
            memberSymbolRowsByKind[result.memberKind, default: [:]][result.typeName, default: [:]][result.typeNodeIndex, default: .empty].append(result.symbolTableRow)
            typeInfoByName[result.typeName, default: [:]][result.typeNodeIndex] = result.typeInfo
        }

        mutating func setMethodDescriptorMemberSymbols(for result: ProcessMemberSymbolResult) {
            methodDescriptorMemberSymbolRowsByKind[result.memberKind, default: [:]][result.typeName, default: [:]][result.typeNodeIndex, default: .empty].append(result.symbolTableRow)
            typeInfoByName[result.typeName, default: [:]][result.typeNodeIndex] = result.typeInfo
        }

        mutating func setProtocolWitnessMemberSymbols(for result: ProcessMemberSymbolResult) {
            protocolWitnessMemberSymbolRowsByKind[result.memberKind, default: [:]][result.typeName, default: [:]][result.typeNodeIndex, default: .empty].append(result.symbolTableRow)
            typeInfoByName[result.typeName, default: [:]][result.typeNodeIndex] = result.typeInfo
        }

        mutating func setObjCThunkMemberSymbols(for result: ProcessMemberSymbolResult) {
            objcThunkMemberSymbolRowsByKind[result.memberKind, default: [:]][result.typeName, default: [:]][result.typeNodeIndex, default: .empty].append(result.symbolTableRow)
            typeInfoByName[result.typeName, default: [:]][result.typeNodeIndex] = result.typeInfo
        }

        mutating func setSpecializedInitializerSymbols(for result: ProcessMemberSymbolResult) {
            specializedInitializerSymbolRowsByKind[result.memberKind, default: [:]][result.typeName, default: [:]][result.typeNodeIndex, default: .empty].append(result.symbolTableRow)
            typeInfoByName[result.typeName, default: [:]][result.typeNodeIndex] = result.typeInfo
        }

        mutating func setGlobalSymbols(for result: ProcessGlobalSymbolResult) {
            globalSymbolRowsByKind[result.kind, default: []].append(result.symbolTableRow)
        }

        mutating func appendThunkAttributeMember(_ member: ThunkAttributeMember, forKind thunkKind: Node.Kind, typeName: String, typeNodeIndex: NodeStore.NodeIndex) {
            thunkAttributeMembersByKindAndTypeName[thunkKind, default: [:]][typeName, default: [:]][typeNodeIndex, default: []].append(member)
        }
    }

    public static let shared = SwiftSymbolIndexStore()

    private let cache = SharedCache<Storage>(evictionGroup: .swiftSymbolStore)

    private init() {}

    /// The image's storage: built on first use, shared with every later
    /// caller, and dropped through ``remove(for:)`` by the declaration
    /// indexer's per-image cleanup.
    ///
    /// Building it collects the symbol table; the demangled index is built
    /// on the first query that needs it (see `Storage.DemangledIndex`).
    public func storage(in machO: some MachORepresentableWithCache) -> Storage? {
        cache.storage(in: machO) { buildSymbolTableStage(for: $0) }
    }

    /// Builds the storage, demangled index included, without consulting or
    /// filling the cache. The baseline measurements time the sweep itself
    /// through this.
    public func buildStorage(for machO: some MachORepresentableWithCache) -> Storage? {
        guard let storage = buildSymbolTableStage(for: machO) else { return nil }
        _ = storage.demangledIndex
        return storage
    }

    /// Builds the storage without consulting or filling the cache and
    /// without its demangled index, so a test can watch which queries build
    /// that index.
    package func buildStorageWithoutDemangledIndexForTesting(for machO: some MachORepresentableWithCache) -> Storage? {
        buildSymbolTableStage(for: machO)
    }

    public func contains(in machO: some MachORepresentableWithCache) -> Bool {
        cache.contains(in: machO)
    }

    public func remove(for machO: some MachORepresentableWithCache) {
        cache.remove(for: machO)
    }

    /// The build sweep's first pass: the symbol table, the offset index, the
    /// symbolic-mangling table and the export facts. It demangles nothing;
    /// the second pass, `buildDemangledIndex(from:progressContinuation:)`,
    /// runs when a query first needs a demangled tree.
    private func buildSymbolTableStage(for machO: some MachORepresentableWithCache) -> Storage? {
        // MachOKitExtensions' sweep collects the Swift names and the
        // symbolic-mangling names into tables of their own, the first with an
        // offset index, both with export facts; it reads a loaded image's names
        // in place (dyld never unloads an image carrying Swift content).
        let sweep = SymbolSweep(sweeping: machO, routing: SwiftSymbolTableRouting())
        let sweptSwiftSymbols = sweep[.swift]
        return Storage(
            symbolTable: sweptSwiftSymbols.symbolTable,
            symbolRowsByOffset: sweptSwiftSymbols.rowsByOffset,
            exportFacts: sweptSwiftSymbols.exportFacts,
            hasLocalSwiftSymbols: sweptSwiftSymbols.hasLocalSymbols,
            symbolicManglingSymbolTable: sweep[.symbolicMangling].symbolTable,
            demangledIndexBuilder: { [self] symbolTable, progressContinuation in
                buildDemangledIndex(from: symbolTable, progressContinuation: progressContinuation)
            }
        )
    }

    /// The build sweep's second pass: every row's name demangled, interned
    /// and classified into the indexes `Storage.DemangledIndex` holds.
    ///
    /// Runs on an 8MB thread: `Storage.demangledIndex(reportingProgressTo:)`
    /// takes one before calling. `demangleAsNodeTransient` — like every
    /// `Demangling` entry point — probes the *calling* thread's remaining
    /// stack and moves the work to an 8MB worker when less than 2MB is left,
    /// blocking on a semaphore until that worker returns. Darwin gives every
    /// thread except the main one a 512KB stack, so on the Swift Concurrency
    /// cooperative worker or libdispatch worker a build runs on, that probe
    /// never passes: without one hop around the whole loop each of a
    /// framework's hundreds of thousands of symbols pays its own thread round
    /// trip. Wrapping the *call sites* instead would be a no-op — a hop that
    /// covers one demangle saves the one it replaces and nothing else.
    private func buildDemangledIndex(
        from symbolTable: SymbolTable,
        progressContinuation: AsyncStream<Progress>.Continuation?
    ) -> Storage.DemangledIndex {
        // Demangle each symbol cache-free onto a transient tree, classify on
        // that tree, and intern the result into the arena builder. Nothing
        // touches the global `NodeCache` and no class trees outlive their
        // wave (NodeStore migration plan, Stage 1). Indexes accumulate
        // directly in their final row-index form (Stage 3), so `freeze()` is
        // followed by a plain move into `Storage`, not a conversion pass.
        //
        // The demangling — half of the sweep — runs a wave of rows ahead on
        // every thread the machine runs at once (`DemanglingWave`); interning
        // and classifying stay on this thread, in row order, so the store and
        // every index come out exactly as a sequential sweep makes them
        // (evolution proposal `machofile-performance`).
        let totalSymbolCount = symbolTable.rowCount

        var builder = NodeStoreBuilder()
        builder.reserveCapacity(expectedSymbolCount: totalSymbolCount)
        var rootNodeIndexByTableRow = [NodeStore.NodeIndex?](repeating: nil, count: totalSymbolCount)
        var rowIndexes = RowIndexes()

        var pendingWave = DemanglingWave.start(rows: 0 ..< min(DemanglingWave.size, totalSymbolCount), of: symbolTable)
        while let wave = pendingWave {
            wave.waitUntilDemangled()
            let nextRows = wave.rows.upperBound ..< min(wave.rows.upperBound + DemanglingWave.size, totalSymbolCount)
            pendingWave = DemanglingWave.start(rows: nextRows, of: symbolTable)

            for row in wave.rows {
                if row % 500 == 0 {
                    progressContinuation?.yield(Progress(currentCount: row, totalCount: totalSymbolCount))
                }

                let symbolTableRow = UInt32(row)
                guard let rootNode = wave.tree(forRow: row) else { continue }
                rootNodeIndexByTableRow[row] = builder.intern(rootNode)

                guard rootNode.isKind(of: .global), let node = rootNode.children.first else { continue }

                rowIndexes.appendSymbolRow(symbolTableRow, for: node.kind)

                if node.kind == .objCAttribute || node.kind == .nonObjCAttribute {
                    if let extracted = processThunkAttributeSymbol(thunkKind: node.kind, rootNode: rootNode, builder: &builder) {
                        rowIndexes.appendThunkAttributeMember(extracted.member, forKind: node.kind, typeName: extracted.typeName, typeNodeIndex: extracted.typeNodeIndex)
                    }
                    // The member the `@objc` thunk enters, filed by the member it
                    // stands for (see `objcThunkMemberSymbolRowsByKind`).
                    if node.kind == .objCAttribute,
                       let entityNode = rootNode.children.first(where: { $0.kind != .objCAttribute }),
                       let result = processMemberSymbol(symbolTableRow, node: entityNode, builder: &builder) {
                        rowIndexes.setObjCThunkMemberSymbols(for: result)
                    }
                    continue
                }

                // An initializing entry point's function signature
                // specialization, filed by the initializer it specializes (see
                // `specializedInitializerSymbolRowsByKind`). It still takes the
                // path below, which files no specialization.
                if node.kind == .functionSignatureSpecialization,
                   let entityNode = rootNode.children.first(where: { $0.kind != .functionSignatureSpecialization }),
                   entityNode.kind == .constructor,
                   let result = processMemberSymbol(symbolTableRow, node: entityNode, builder: &builder) {
                    rowIndexes.setSpecializedInitializerSymbols(for: result)
                }

                if rootNode.isGlobal {
                    if !symbolTable.isExternal(atRow: symbolTableRow) {
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
                        if symbolTable.canonicalOffset(atRow: symbolTableRow) > 0 {
                            rowIndexes.opaqueTypeDescriptorSymbolRowByNodeIndex[builder.intern(memberSymbol)] = symbolTableRow
                        }
                    } else {
                        if let result = processMemberSymbol(symbolTableRow, node: node, builder: &builder) {
                            rowIndexes.setMemberSymbols(for: result)
                        }
                    }
                }
            }
        }
        progressContinuation?.yield(Progress(currentCount: totalSymbolCount, totalCount: totalSymbolCount))

        return Storage.DemangledIndex(
            nodeStore: builder.freeze(),
            rootNodeIndexByTableRow: rootNodeIndexByTableRow,
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
        // A SE-0507 `borrow` / `mutate` accessor is the property's read /
        // write accessor when it declares one: such a property has no getter
        // or setter symbol of its own, so skipping them dropped it whole.
        // A SE-0400 init accessor belongs to its property the same way
        // (evolution proposal `init-accessor-recovery`); the kind index above
        // keeps listing it too, which `@Observable` recovery reads.
        case .getter,
             .setter,
             .borrowAccessor,
             .mutateAccessor,
             .initAccessor:
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

    /// Extracts `(typeName, typeNodeIndex, ThunkAttributeMember)` from a thunk
    /// symbol whose root demangled node has an attribute marker child
    /// (`.objCAttribute` / `.nonObjCAttribute`). The parent context is also
    /// interned (same `.type`-wrapped shape as the member indexes' keys) so
    /// consumers can tell same-named private types apart. Returns `nil` if the
    /// thunk does not wrap a named member whose parent context can be resolved
    /// to a Swift type name.
    private func processThunkAttributeSymbol(
        thunkKind: Node.Kind,
        rootNode: Node,
        builder: inout NodeStoreBuilder
    ) -> (typeName: String, typeNodeIndex: NodeStore.NodeIndex, member: ThunkAttributeMember)? {
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
        let typeNodeIndex = builder.intern(kind: .type, children: [builder.intern(contextNode)])

        let isInit = unwrappedMemberNode.kind == .allocator || unwrappedMemberNode.kind == .constructor

        return (
            typeName: typeName,
            typeNodeIndex: typeNodeIndex,
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
             .setter,
             .borrowAccessor,
             .mutateAccessor:
            if let variableNode = node.children.first, variableNode.kind == .variable {
                return processGlobalSymbol(symbolTableRow, node: variableNode)
            }
        default:
            break
        }
        return nil
    }

    public func allSymbols(in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return storage.symbolRowsByKind.values.flatMap { storage.demangledSymbols(atRows: $0) }
    }

    /// The text of every `.module` node in the trees `allSymbols(in:)`
    /// returns, in the order a preorder walk of those trees, one symbol after
    /// another, meets them first — together with how many symbols that is.
    ///
    /// The walk reads the node store directly and enters each subtree once:
    /// identical subtrees share one node in the store, and a subtree met
    /// again can add no name its first visit did not already add, so
    /// skipping it changes neither the names nor their order. Walking every
    /// symbol's whole tree instead — what a caller of `allSymbols(in:)` does —
    /// cost SwiftUI's interface about two seconds (evolution proposal
    /// `machofile-performance`).
    package func moduleNamesInAllSymbols(in machO: some MachORepresentableWithCache) -> (symbolCount: Int, moduleNames: OrderedSet<String>) {
        guard let storage = storage(in: machO) else { return (0, []) }
        let demangledIndex = storage.demangledIndex
        var symbolCount = 0
        var moduleNames: OrderedSet<String> = []
        var visitedNodeIndices: Set<NodeStore.NodeIndex> = []
        visitedNodeIndices.reserveCapacity(demangledIndex.nodeStore.nodeCount)
        var pendingNodes: [NodeReference] = []
        for rows in demangledIndex.symbolRowsByKind.values {
            for row in rows {
                guard let rootNodeIndex = demangledIndex.rootNodeIndexByTableRow[Int(row)] else { continue }
                symbolCount += 1
                pendingNodes.append(demangledIndex.nodeStore.reference(at: rootNodeIndex))
                while let node = pendingNodes.popLast() {
                    guard visitedNodeIndices.insert(node.nodeIndex).inserted else { continue }
                    if node.kind == .module, let moduleName = node.text {
                        moduleNames.append(moduleName)
                    }
                    pendingNodes.append(contentsOf: node.children.reversed())
                }
            }
        }
        return (symbolCount, moduleNames)
    }

    public func symbolsByKind(in machO: some MachORepresentableWithCache) -> OrderedDictionary<Node.Kind, [DemangledSymbol]> {
        guard let storage = storage(in: machO) else { return [:] }
        return storage.symbolRowsByKind.mapValues { storage.demangledSymbols(atRows: $0) }
    }

    /// Name-only lookup: first-wins across the (rare) same-named private
    /// types colliding on the stripped interface print. Prefer the
    /// node-taking overload whenever the caller holds the type's context
    /// node — the name alone cannot tell same-named private types apart.
    public func typeInfo(for name: String, in machO: some MachORepresentableWithCache) -> TypeInfo? {
        return storage(in: machO)?.typeInfoByName[name]?.values.first
    }

    /// Structural counterpart: resolves the `TypeInfo` of exactly the type
    /// whose context node matches `node`, so same-named private types each
    /// answer with their own kind.
    public func typeInfo(for name: String, node: NodeReference, in machO: some MachORepresentableWithCache) -> TypeInfo? {
        guard let storage = storage(in: machO) else { return nil }
        guard let typeInfoByTypeNodeIndex = storage.typeInfoByName[name] else { return nil }
        return typeInfoByTypeNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) })?.value
    }

    public func symbols(of kinds: Node.Kind..., in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { storage.demangledSymbols(atRows: storage.symbolRowsByKind[$0] ?? []) }.reduce(into: []) { $0 += $1 }
    }

    /// The number of symbols of `kinds` — O(1) per kind on the row index,
    /// for callers (the interface header's dispatch-thunk count) that need
    /// only the count and would otherwise materialize a `DemangledSymbol`
    /// array to throw it away.
    public func symbolCount(of kinds: Node.Kind..., in machO: some MachORepresentableWithCache) -> Int {
        guard let storage = storage(in: machO) else { return 0 }
        return kinds.reduce(0) { $0 + (storage.symbolRowsByKind[$1]?.count ?? 0) }
    }

    /// Whether the mangled `name` has an export-trie entry in `machO`
    /// (evolution proposal 0008). Answers a symbol-table FACT, not an
    /// access level: `false` means "no export-trie entry for this name",
    /// which is what a `// not exported` annotation may honestly claim.
    /// Returns `nil` when the image carries no export information at all
    /// (no trie, or the store is unavailable) — then the distinction is
    /// meaningless and callers should not annotate.
    public func isExported(name: String, in machO: some MachORepresentableWithCache) -> Bool? {
        guard let storage = storage(in: machO) else { return nil }
        return storage.isExported(name: name)
    }

    /// Whether `machO` carries export information at all — the condition
    /// under which ``isExported(name:in:)`` answers `true` / `false` rather
    /// than `nil`. A verdict that rests on something other than a trie entry
    /// (a private declaration, which the compiler never exports) still
    /// needs it: without a trie, nothing in the image is judged.
    package func hasExportInformation(in machO: some MachORepresentableWithCache) -> Bool {
        storage(in: machO)?.exportFacts.hasExportInformation ?? false
    }

    /// Whether the build sweep collected a symbol with exactly this name —
    /// presence in the symtab/trie population, regardless of export status.
    /// Backs the dump path's `@objc` exemption (evolution proposal 0008):
    /// an `@objc` member's ObjC entry point is its implementation name plus
    /// the `To` thunk suffix, so presence of that name identifies the
    /// member as objc_msgSend-reachable without demangling anything.
    public func containsSymbol(named name: String, in machO: some MachORepresentableWithCache) -> Bool {
        guard let storage = storage(in: machO) else { return false }
        return storage.symbolTable.row(forName: name) != nil
    }

    /// The offset `symbols(for:in:)` files the symbol named exactly `name`
    /// under, or `nil` when the sweep collected no such symbol. A name only
    /// a debug-map entry reserved has no offset, and answers `nil`.
    package func offset(ofSymbolNamed name: String, in machO: some MachORepresentableWithCache) -> Int? {
        guard let storage = storage(in: machO), let row = storage.symbolTable.row(forName: name) else { return nil }
        let offset = storage.symbolTable.canonicalOffset(atRow: row)
        guard storage.symbolRowsByOffset[offset]?.contains(row) == true else { return nil }
        return offset
    }

    /// The mangled suffixes deriving a member's exported entry points from
    /// its implementation symbol: `Tj` dispatch thunk, `Tq` method
    /// descriptor, `Tu` async function pointer, and the thunk's own async
    /// pointer `TjTu`. Swift mangling appends them verbatim.
    private static let derivedExportSuffixes = ["Tj", "Tq", "Tu", "TjTu"]

    /// `isExported(name:in:)` extended over the member's derived
    /// entry-point forms. A library-evolution build routinely keeps the
    /// implementation symbol private while exporting the `Tj` dispatch
    /// thunk (external callers dispatch through it) — so an implementation
    /// symbol missing from the trie proves nothing on its own, and a
    /// member is honestly "not exported" only when NONE of its forms are
    /// (issue #106 verified exactly this way: an export-table search for
    /// any symbol of the member).
    public func isExportedIncludingDerivedSymbols(name: String, in machO: some MachORepresentableWithCache) -> Bool? {
        guard let storage = storage(in: machO) else { return nil }
        guard let isExported = storage.isExported(name: name) else { return nil }
        if isExported {
            return true
        }
        for suffix in Self.derivedExportSuffixes where storage.isExported(name: name + suffix) == true {
            return true
        }
        return false
    }

    /// The export verdict of a member whose entry points are `names` — a
    /// function's one symbol, a property's or subscript's accessors: `true`
    /// as soon as one of them is exported in its own or a derived form
    /// (``isExportedIncludingDerivedSymbols(name:in:)``), `false` only when
    /// none is, `nil` when `names` is empty or the image carries no export
    /// information. The interface's `// not exported` annotation and the ABI
    /// snapshot's per-member verdict both ask this, so the two cannot
    /// disagree.
    public func isExportedIncludingDerivedSymbols(names: [String], in machO: some MachORepresentableWithCache) -> Bool? {
        guard !names.isEmpty else { return nil }
        for name in names {
            guard let isExported = isExportedIncludingDerivedSymbols(name: name, in: machO) else { return nil }
            if isExported {
                return true
            }
        }
        return false
    }

    /// Whether `machO`'s symbol table carries at least one local
    /// (non-external) Swift symbol (evolution proposal
    /// `evolution-unobservable-presence`). `false` for an image stripped of
    /// its local symbols — SwiftUI in the macOS 13.0–14.8 dyld shared caches
    /// — where a non-exported declaration has no name the index could find,
    /// so its absence there says nothing about whether it exists. `nil` when
    /// the store is unavailable.
    public func hasLocalSwiftSymbols(in machO: some MachORepresentableWithCache) -> Bool? {
        storage(in: machO)?.hasLocalSwiftSymbols
    }

    /// Returns the pre-extracted thunk-attribute members whose parent type
    /// name matches `typeName`. `thunkKind` is the demangler attribute marker
    /// kind (e.g. `.objCAttribute`, `.nonObjCAttribute`). Lookup is O(1) in the
    /// typeName bucket; no per-type scan of all thunk symbols is needed.
    /// Flattens every context-node bucket under the name — same-named private
    /// types are merged here; prefer the node-taking overload when the caller
    /// can supply the type's context node.
    public func thunkAttributeMembers(
        of thunkKind: Node.Kind,
        for typeName: String,
        in machO: some MachORepresentableWithCache
    ) -> [ThunkAttributeMember] {
        guard let membersByTypeNodeIndex = storage(in: machO)?.thunkAttributeMembersByKindAndTypeName[thunkKind]?[typeName] else { return [] }
        return membersByTypeNodeIndex.values.flatMap { $0 }
    }

    /// Structural counterpart: returns only the members whose parent context
    /// node matches `node`, so a same-named private sibling's `@objc` /
    /// `@nonobjc` thunks never stamp attributes onto this type's members.
    public func thunkAttributeMembers(
        of thunkKind: Node.Kind,
        for typeName: String,
        node: NodeReference,
        in machO: some MachORepresentableWithCache
    ) -> [ThunkAttributeMember] {
        guard let storage = storage(in: machO) else { return [] }
        guard let membersByTypeNodeIndex = storage.thunkAttributeMembersByKindAndTypeName[thunkKind]?[typeName] else { return [] }
        guard let matched = membersByTypeNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) }) else { return [] }
        return matched.value
    }

    /// Same lookup as the `NodeReference` overload, for callers holding an
    /// externally demangled `Node` (`SymbolicDemangler.demangleContext` output in
    /// the dump path) rather than a store-backed reference.
    public func thunkAttributeMembers(
        of thunkKind: Node.Kind,
        for typeName: String,
        node: Node,
        in machO: some MachORepresentableWithCache
    ) -> [ThunkAttributeMember] {
        guard let storage = storage(in: machO) else { return [] }
        guard let membersByTypeNodeIndex = storage.thunkAttributeMembersByKindAndTypeName[thunkKind]?[typeName] else { return [] }
        guard let matched = membersByTypeNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) }) else { return [] }
        return matched.value
    }

    public func memberSymbols(of kinds: MemberKind..., in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let memberRows = storage.memberSymbolRowsByKind[kind] else { return [] }
            return memberRows.values.flatMap { rowsByTypeNodeIndex in
                rowsByTypeNodeIndex.values.flatMap { storage.demangledSymbols(atRows: $0) }
            }
        }.reduce(into: []) { $0 += $1 }
    }

    public func memberSymbols(of kinds: MemberKind..., for name: String, in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.memberSymbolRowsByKind[kind]?[name] else { return [] }
            return rowsByTypeNodeIndex.values.flatMap { storage.demangledSymbols(atRows: $0) }
        }.reduce(into: []) { $0 += $1 }
    }

    public func memberSymbols(of kinds: MemberKind..., for name: String, node: Node, in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        // Callers hold an externally demangled `Node` (SymbolicDemangler context
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

    public func memberSymbols(of kinds: MemberKind..., for name: String, node: NodeReference, in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
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

    /// Keyed on `StructuralNodeReferenceKey`, not a bare `NodeReference`: the
    /// keys are references into this image's frozen arena, so a caller probing
    /// the result with a tree it demangled itself would miss every entry under
    /// store-identity equality — silently, and with no compile error. The
    /// in-package consumer only iterates, but the vended contract has to hold
    /// for lookups too (`NodeStoreMigrationOpenIssues.md` item 3, reopened in the
    /// PR #103 round-three review and recorded in `ReviewAdjudications.md` A9).
    public func memberSymbols(of kinds: MemberKind..., excluding names: borrowing Set<String>, in machO: some MachORepresentableWithCache) -> OrderedDictionary<StructuralNodeReferenceKey, OrderedDictionary<MemberKind, [DemangledSymbol]>> {
        guard let storage = storage(in: machO) else { return [:] }
        var result: OrderedDictionary<StructuralNodeReferenceKey, OrderedDictionary<MemberKind, [DemangledSymbol]>> = [:]
        for kind in kinds {
            guard let memberRows = storage.memberSymbolRowsByKind[kind] else { continue }
            for (typeName, rowsByTypeNodeIndex) in memberRows where !names.contains(typeName) {
                for (typeNodeIndex, rows) in rowsByTypeNodeIndex {
                    result[StructuralNodeReferenceKey(storage.nodeStore.reference(at: typeNodeIndex)), default: [:]][kind, default: []].append(contentsOf: storage.demangledSymbols(atRows: rows))
                }
            }
        }
        return result
    }

    public func methodDescriptorMemberSymbols(of kinds: MemberKind..., in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let memberRows = storage.methodDescriptorMemberSymbolRowsByKind[kind] else { return [] }
            return memberRows.values.flatMap { rowsByTypeNodeIndex in
                rowsByTypeNodeIndex.values.flatMap { storage.demangledSymbols(atRows: $0) }
            }
        }.reduce(into: []) { $0 += $1 }
    }

    public func methodDescriptorMemberSymbols(of kinds: MemberKind..., for name: String, in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.methodDescriptorMemberSymbolRowsByKind[kind]?[name] else { return [] }
            return rowsByTypeNodeIndex.values.flatMap { storage.demangledSymbols(atRows: $0) }
        }.reduce(into: []) { $0 += $1 }
    }

    public func methodDescriptorMemberSymbols(of kinds: MemberKind..., for name: String, node: Node, in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        // Same disambiguation as `memberSymbols(of:for:node:in:)`: the
        // stripped name bucket can hold several same-named private types,
        // and only the structural context-node match picks the right one.
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.methodDescriptorMemberSymbolRowsByKind[kind]?[name] else { return [] }
            guard let matched = rowsByTypeNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) }) else { return [] }
            return storage.demangledSymbols(atRows: matched.value)
        }.reduce(into: []) { $0 += $1 }
    }

    /// Same lookup as the `Node` overload, for callers holding a store-backed
    /// reference — possibly minted into a different store than the index's own
    /// (a `TypeName` mini store, for example): same-store keys match in O(1)
    /// via index equality, cross-store keys by a structural walk over the
    /// handful of bucket entries.
    public func methodDescriptorMemberSymbols(of kinds: MemberKind..., for name: String, node: NodeReference, in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.methodDescriptorMemberSymbolRowsByKind[kind]?[name] else { return [] }
            guard let matched = rowsByTypeNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) }) else { return [] }
            return storage.demangledSymbols(atRows: matched.value)
        }.reduce(into: []) { $0 += $1 }
    }

    public func protocolWitnessMemberSymbols(of kinds: MemberKind..., in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let memberRows = storage.protocolWitnessMemberSymbolRowsByKind[kind] else { return [] }
            return memberRows.values.flatMap { rowsByTypeNodeIndex in
                rowsByTypeNodeIndex.values.flatMap { storage.demangledSymbols(atRows: $0) }
            }
        }.reduce(into: []) { $0 += $1 }
    }

    public func protocolWitnessMemberSymbols(of kinds: MemberKind..., for name: String, in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.protocolWitnessMemberSymbolRowsByKind[kind]?[name] else { return [] }
            return rowsByTypeNodeIndex.values.flatMap { storage.demangledSymbols(atRows: $0) }
        }.reduce(into: []) { $0 += $1 }
    }

    /// The `@objc` thunks (`$s…To`) of the members of the type named `name`,
    /// each the thunk's own symbol: its name ends in `To` and its tree leads
    /// with the `objCAttribute` marker. Flattens every context-node bucket
    /// under the name; prefer a node-taking overload when the caller has the
    /// type's context node.
    public func objcThunkMemberSymbols(of kinds: MemberKind..., for name: String, in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.objcThunkMemberSymbolRowsByKind[kind]?[name] else { return [] }
            return rowsByTypeNodeIndex.values.flatMap { storage.demangledSymbols(atRows: $0) }
        }.reduce(into: []) { $0 += $1 }
    }

    /// Same disambiguation as `memberSymbols(of:for:node:in:)`, for callers
    /// holding an externally demangled `Node`.
    public func objcThunkMemberSymbols(of kinds: MemberKind..., for name: String, node: Node, in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.objcThunkMemberSymbolRowsByKind[kind]?[name] else { return [] }
            guard let matched = rowsByTypeNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) }) else { return [] }
            return storage.demangledSymbols(atRows: matched.value)
        }.reduce(into: []) { $0 += $1 }
    }

    /// Same lookup as the `Node` overload, for callers holding a store-backed
    /// reference, possibly minted into a different store than the index's own.
    public func objcThunkMemberSymbols(of kinds: MemberKind..., for name: String, node: NodeReference, in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.objcThunkMemberSymbolRowsByKind[kind]?[name] else { return [] }
            guard let matched = rowsByTypeNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) }) else { return [] }
            return storage.demangledSymbols(atRows: matched.value)
        }.reduce(into: []) { $0 += $1 }
    }

    /// The `@objc` thunks of every type's members, grouped like
    /// `memberSymbols(of:excluding:in:)` and keyed structurally for the same
    /// reason.
    public func objcThunkMemberSymbols(of kinds: MemberKind..., excluding names: borrowing Set<String>, in machO: some MachORepresentableWithCache) -> OrderedDictionary<StructuralNodeReferenceKey, OrderedDictionary<MemberKind, [DemangledSymbol]>> {
        guard let storage = storage(in: machO) else { return [:] }
        var result: OrderedDictionary<StructuralNodeReferenceKey, OrderedDictionary<MemberKind, [DemangledSymbol]>> = [:]
        for kind in kinds {
            guard let memberRows = storage.objcThunkMemberSymbolRowsByKind[kind] else { continue }
            for (typeName, rowsByTypeNodeIndex) in memberRows where !names.contains(typeName) {
                for (typeNodeIndex, rows) in rowsByTypeNodeIndex {
                    result[StructuralNodeReferenceKey(storage.nodeStore.reference(at: typeNodeIndex)), default: [:]][kind, default: []].append(contentsOf: storage.demangledSymbols(atRows: rows))
                }
            }
        }
        return result
    }

    /// The function signature specializations of the initializing entry
    /// points of the type named `name` (`$s…fcTf…`), each the specialization's
    /// own symbol: its tree leads with the `functionSignatureSpecialization`
    /// node, the `constructor` follows. Only `constructor` kinds are filed.
    /// Flattens every context-node bucket under the name; prefer the
    /// node-taking overload when the caller has the type's context node.
    public func specializedInitializerSymbols(of kinds: MemberKind..., for name: String, in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.specializedInitializerSymbolRowsByKind[kind]?[name] else { return [] }
            return rowsByTypeNodeIndex.values.flatMap { storage.demangledSymbols(atRows: $0) }
        }.reduce(into: []) { $0 += $1 }
    }

    /// Same disambiguation as `memberSymbols(of:for:node:in:)`, for callers
    /// holding a store-backed reference, possibly minted into a different
    /// store than the index's own.
    public func specializedInitializerSymbols(of kinds: MemberKind..., for name: String, node: NodeReference, in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.specializedInitializerSymbolRowsByKind[kind]?[name] else { return [] }
            guard let matched = rowsByTypeNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) }) else { return [] }
            return storage.demangledSymbols(atRows: matched.value)
        }.reduce(into: []) { $0 += $1 }
    }

    /// The initializing entry points' specializations of every type, grouped
    /// like `memberSymbols(of:excluding:in:)` and keyed structurally for the
    /// same reason.
    public func specializedInitializerSymbols(of kinds: MemberKind..., excluding names: borrowing Set<String>, in machO: some MachORepresentableWithCache) -> OrderedDictionary<StructuralNodeReferenceKey, OrderedDictionary<MemberKind, [DemangledSymbol]>> {
        guard let storage = storage(in: machO) else { return [:] }
        var result: OrderedDictionary<StructuralNodeReferenceKey, OrderedDictionary<MemberKind, [DemangledSymbol]>> = [:]
        for kind in kinds {
            guard let memberRows = storage.specializedInitializerSymbolRowsByKind[kind] else { continue }
            for (typeName, rowsByTypeNodeIndex) in memberRows where !names.contains(typeName) {
                for (typeNodeIndex, rows) in rowsByTypeNodeIndex {
                    result[StructuralNodeReferenceKey(storage.nodeStore.reference(at: typeNodeIndex)), default: [:]][kind, default: []].append(contentsOf: storage.demangledSymbols(atRows: rows))
                }
            }
        }
        return result
    }

    public func globalSymbols(of kinds: GlobalKind..., in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { storage.demangledSymbols(atRows: storage.globalSymbolRowsByKind[$0] ?? []) }.reduce(into: []) { $0 += $1 }
    }

    /// Structurally keyed for the same reason as `memberSymbols(of:excluding:in:)`
    /// above — and with the same precedent behind it: the single-item sibling
    /// `opaqueTypeDescriptorSymbol(for:)` was converted to a structural key after
    /// store-identity keys silently dropped the `override` keyword and the
    /// vtable-offset comments (the Stage 5a regression). This bulk form was left
    /// behind by that fix.
    public func allOpaqueTypeDescriptorSymbols(in machO: some MachORepresentableWithCache) -> OrderedDictionary<StructuralNodeReferenceKey, DemangledSymbol>? {
        guard let storage = storage(in: machO) else { return nil }
        var result: OrderedDictionary<StructuralNodeReferenceKey, DemangledSymbol> = [:]
        for (nodeIndex, row) in storage.opaqueTypeDescriptorSymbolRowByNodeIndex {
            guard let demangledSymbol = storage.demangledSymbol(atRow: row) else { continue }
            result[StructuralNodeReferenceKey(storage.nodeStore.reference(at: nodeIndex))] = demangledSymbol
        }
        return result
    }

    public func opaqueTypeDescriptorSymbol(for node: Node, in machO: some MachORepresentableWithCache) -> DemangledSymbol? {
        // The caller's `node` was demangled during printing; keys live in the
        // frozen store, so the match has to be structural — but structural does
        // not have to mean linear. `StructuralNodeReferenceKey` hashes a queried
        // `Node` the same way it hashes a stored `NodeReference`, so this is one
        // probe (see `opaqueTypeDescriptorSymbolRowByMemberNode` for why the
        // identifier-bucketed scan this replaced was quadratic in practice).
        guard let storage = storage(in: machO) else { return nil }
        guard let symbolTableRow = storage.opaqueTypeDescriptorSymbolRowByMemberNode[.init(querying: node)] else { return nil }
        return storage.demangledSymbol(atRow: symbolTableRow)
    }

    package func symbols(for offset: Int, in machO: some MachORepresentableWithCache) -> Symbols? {
        guard let storage = storage(in: machO), let rows = storage.symbolRowsByOffset[offset], !rows.isEmpty else { return nil }
        return .init(offset: offset, symbols: rows.map { storage.symbol(atRow: $0, offset: offset) })
    }

    /// Of the symbols `symbols(for:in:)` lists at `offset`, the ones whose
    /// owner — named by `ownerKind`, printed with `options` — prints as
    /// `ownerName`, in that query's order, each paired with its demangled
    /// tree: what a conformance asks an implementation address for when it
    /// attributes a witness, and a protocol a requirement's or default
    /// implementation's address. Each value is standalone and stamped with
    /// the queried offset, as a value built from that query's `Symbol`
    /// would be.
    ///
    /// One grouping per offset, owner rule and options, kept with the
    /// image's index, answers every later question about it; see
    /// `Storage.rows(at:ownedBy:ownerKind:options:)`.
    package func symbols(for offset: Int, ownedBy ownerName: String, ownerKind: SymbolOwnerKind, printedWith options: DemangleOptions, in machO: some MachORepresentableWithCache) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return storage.rows(at: offset, ownedBy: ownerName, ownerKind: ownerKind, options: options).compactMap { row in
            guard let rootNodeIndex = storage.rootNodeIndexByTableRow[Int(row)] else { return nil }
            return DemangledSymbol(symbol: storage.symbol(atRow: row, offset: offset), demangledNode: storage.nodeStore.reference(at: rootNodeIndex))
        }
    }

    /// The image's symbolic-mangling symbols — `_symbolic ` and
    /// `_default assoc type ` — as the build sweep collected them (evolution
    /// proposal `symbolic-mangling-symbol-index`), building the index on
    /// first use like every other query here. `nil` only when no index could
    /// be built.
    package func symbolicManglingSymbols(in machO: some MachORepresentableWithCache) -> SymbolicManglingSymbols? {
        guard let storage = storage(in: machO) else { return nil }
        return SymbolicManglingSymbols(symbolTable: storage.symbolicManglingSymbolTable)
    }

    /// Store-backed handle for a symbol's demangled tree. Hits the frozen
    /// image store for symbols covered by the build sweep; symbols outside
    /// the sweep are demangled once into the storage's shared late-name side
    /// store (`lateDemangledNode(forName:)`, which caches the verdict —
    /// rejections included), so every caller receives a uniform `NodeReference`.
    package func demangledNodeReference(for symbol: Symbol, in machO: some MachORepresentableWithCache) -> NodeReference? {
        guard let cacheStorage = storage(in: machO) else { return nil }
        // Matched on name alone. A demangled tree is a pure function of the
        // symbol name and the flat table already holds one row per unique
        // name, so the row's own offset carries no extra information here —
        // whereas comparing it against the queried symbol's offset can only
        // ever reject an otherwise valid hit. It used to do exactly that for
        // a whole image: rows store the *canonical* (cache-adjusted) offset
        // while `symbols(for:in:)` stamps each vended `Symbol` with the offset
        // it was queried by, so on the dyld-cache path every symbol missed and
        // fell through to the per-symbol mini store below — the same
        // cross-store split `StructuralNodeReferenceKey` exists to absorb.
        //
        // Several symbols sharing one offset is normal (they differ by name)
        // and is unaffected: each name resolves to its own row. The lookup
        // is a byte-level binary search over the table's name-order
        // permutation (proposal 0001) — the name-keyed dictionary it
        // replaces retained every symbol name for the storage's lifetime.
        if let row = cacheStorage.symbolTable.row(forName: symbol.name) {
            // The sweep already ran every table row through the demangler
            // once; a `nil` root records that it rejected this name. The
            // late path runs the *same* demangler (`NodeStoreBuilder.demangle`
            // is `demangleAsNodeTransient` + intern), so falling through
            // could only re-pay the failed demangle — under the late-cache
            // lock, once per query. `demangledOverrideSymbol` probes
            // candidate symbols in a loop, which made that a hot path.
            guard let rootNodeIndex = cacheStorage.rootNodeIndexByTableRow[Int(row)] else { return nil }
            return cacheStorage.nodeStore.reference(at: rootNodeIndex)
        }
        return cacheStorage.lateDemangledNode(forName: symbol.name)
    }

    package func demangledNode(for symbol: Symbol, in machO: some MachORepresentableWithCache) -> Node? {
        return demangledNodeReference(for: symbol, in: machO)?.materialize()
    }

    public struct Progress: Sendable {
        public let currentCount: Int
        public let totalCount: Int
    }

    /// Builds the image's whole index, demangled trees included.
    public func prepare(in machO: some MachORepresentableWithCache) {
        _ = storage(in: machO)?.demangledIndex
    }

    /// Builds the image's whole index, reporting the demangling progress —
    /// the symbol table itself is collected without demangling, too quickly
    /// to report.
    public func prepareWithProgress(in machO: some MachORepresentableWithCache) -> AsyncStream<Progress> {
        let (stream, continuation) = AsyncStream<Progress>.makeStream()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { continuation.finish() }
            guard let self else { return }
            // The continuation flows into the demangled index's build as an
            // argument only. No shared instance state is involved, so
            // concurrent calls cannot interfere with each other's progress
            // streams; a call that finds the index built reports nothing.
            _ = self.storage(in: machO)?.demangledIndex(reportingProgressTo: continuation)
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
             .borrowAccessor,
             .mutateAccessor,
             .initAccessor,
             .methodDescriptor,
             .protocolWitness,
             .variable:
            return true
        default:
            return false
        }
    }

    fileprivate var typeKind: SwiftSymbolIndexStore.TypeInfo.Kind? {
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
    static let liveValue: SwiftSymbolIndexStore = .shared
    static let testValue: SwiftSymbolIndexStore = .shared
}

@_spi(ForSymbolViewer)
@_spi(Internals)
extension DependencyValues {
    public var swiftSymbolIndexStore: SwiftSymbolIndexStore {
        get { self[SymbolIndexStoreKey.self] }
        set { self[SymbolIndexStoreKey.self] = newValue }
    }
}

extension DemanglingNode {
    package var isGlobal: Bool {
        guard let first = children.first else { return false }
        guard first.isKind(of: .getter, .setter, .borrowAccessor, .mutateAccessor, .function, .variable) else { return false }
        if first.isKind(of: .getter, .setter, .borrowAccessor, .mutateAccessor), let variable = first.children.first, variable.isKind(of: .variable) {
            return variable.children.first?.isKind(of: .module) ?? false
        } else {
            return first.children.first?.isKind(of: .module) ?? false
        }
    }

    /// An init accessor is one: without it, its node read as a property's
    /// storage (`isStoredVariable`) and could stand for the declaration.
    package var isAccessor: Bool {
        return isKind(of: .getter, .setter, .modifyAccessor, .readAccessor, .borrowAccessor, .mutateAccessor, .initAccessor)
    }
}

extension DemanglingNode where Self: Sequence<Self> {
    package var hasAccessor: Bool {
        return contains { $0.isAccessor }
    }
}

/// The demangled trees of a run of symbol table rows, demangled on every
/// thread the machine runs at once while the build sweep interns the run
/// before it.
///
/// Each batch takes one hop to a large stack (`StackSafeExecutor`) and
/// demangles all of its names there: a demangle on a 512KB thread hops once
/// per name otherwise. The tree of a row is a pure function of its name, so
/// which thread demangles it changes nothing the sweep makes of it.
final class DemanglingWave: @unchecked Sendable {
    /// Rows one thread demangles per large-stack hop.
    private static let batchSize = 512

    /// Rows per wave: a batch for every thread the machine runs at once, at
    /// most sixteen, so two waves of trees — the one being interned and the
    /// one being demangled — stay a few megabytes.
    static let size = batchSize * max(1, min(ProcessInfo.processInfo.activeProcessorCount, 16))

    let rows: Range<Int>

    /// One slot per row, each written by the one batch that owns the row.
    private let trees: UnsafeMutableBufferPointer<Node?>

    private let group = DispatchGroup()

    private init(rows: Range<Int>) {
        self.rows = rows
        self.trees = .allocate(capacity: rows.count)
        self.trees.initialize(repeating: nil)
    }

    deinit {
        _ = trees.deinitialize()
        trees.deallocate()
    }

    /// Starts demangling the names of `rows`, or returns `nil` for none.
    static func start(rows: Range<Int>, of symbolTable: SymbolTable) -> DemanglingWave? {
        guard !rows.isEmpty else { return nil }
        let wave = DemanglingWave(rows: rows)
        let batchCount = (rows.count + batchSize - 1) / batchSize
        // A private serial queue: it targets an overcommit root queue, which
        // gets a thread whatever the cooperative pool is doing. `global()` —
        // and a private concurrent queue, which targets the same root — does
        // not: while every cooperative thread of the class is blocked (first
        // readers on each of them, waiting on their large-stack hops), they
        // still count against the class's width, the block never starts, and
        // the builder in `waitUntilDemangled()` waits for ever. That hung the
        // whole test process on a 10-core machine. `concurrentPerform` runs
        // iterations on its calling thread too, so a wave no other thread
        // joins still finishes.
        let qualityOfService = DispatchQoS.QoSClass(rawValue: qos_class_self()) ?? .default
        let queue = DispatchQueue(label: "com.machoswiftsection.symbols.demangling-wave", qos: DispatchQoS(qosClass: qualityOfService, relativePriority: 0))
        queue.async(group: wave.group) {
            DispatchQueue.concurrentPerform(iterations: batchCount) { batchIndex in
                let batchStart = rows.lowerBound + batchIndex * batchSize
                let batchRows = batchStart ..< min(batchStart + batchSize, rows.upperBound)
                StackSafeExecutor.withLargeStack {
                    for row in batchRows {
                        wave.trees[row - rows.lowerBound] = try? demangleAsNodeTransient(symbolTable.materializedName(atRow: UInt32(row)))
                    }
                }
            }
        }
        return wave
    }

    func waitUntilDemangled() {
        group.wait()
    }

    /// The row's demangled tree, or `nil` for a name the demangler rejected.
    func tree(forRow row: Int) -> Node? {
        trees[row - rows.lowerBound]
    }
}
