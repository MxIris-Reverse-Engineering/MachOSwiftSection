import Foundation
import FoundationToolbox
import MachOKit
import MachOKitExtensions
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

    public final class Storage: @unchecked Sendable {
        typealias MemberSymbolRows = OrderedDictionary<String, OrderedDictionary<NodeStore.NodeIndex, SymbolRowBucket>>

        /// The frozen arena holding every demangled node of this image.
        /// All `NodeReference` values vended by this storage point into it.
        let nodeStore: NodeStore

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

        let symbolRowsByKind: OrderedDictionary<Node.Kind, [UInt32]>

        /// Plain `Dictionary`: the only consumer is the keyed lookup in
        /// `symbols(for:in:)` — nothing iterates it in order (proposal 0001
        /// rider; the former `OrderedDictionary` paid an ordering table for
        /// hundreds of thousands of entries nobody read). Values are
        /// `SymbolRowBucket` (proposal 0003): the dominant single-row case
        /// stays inline in the dictionary slot instead of paying a per-key
        /// array allocation.
        let symbolRowsByOffset: [Int: SymbolRowBucket]

        /// Like the member indexes, bucketed by printed type name first and
        /// the interned parent-context node second, so same-named private
        /// types' thunk attributes never cross-stamp each other's members.
        let thunkAttributeMembersByKindAndTypeName: [Node.Kind: [String: OrderedDictionary<NodeStore.NodeIndex, [ThunkAttributeMember]>]]

        /// Export-trie facts for the image (evolution proposal 0008), the
        /// backing for `isExported(name:)`. Collected explicitly during the
        /// build sweep because no existing structure records them: both
        /// symtab collection legs filter on `!nlist.isExternal` (local
        /// symbols only), so an exported symbol's row is minted by the
        /// export-trie leg — but that leg's row-minting is *conditional*
        /// (only names the symtab missed, only entries carrying an offset),
        /// so "row came from the trie leg" is not recoverable after the
        /// fact and offset-less re-export entries never mint a row at all.
        struct ExportFacts {
            /// One bit per `symbolTable` row: set when the row's name has an
            /// export-trie entry. Sized `(rowCount + 63) / 64` words — ~23 KB
            /// for a 185k-row SwiftUI-scale table.
            var exportedRowBitmap: [UInt64] = []

            /// Exported Swift names with no row home: offset-less trie
            /// entries (re-exports) and names whose row minting was refused
            /// by the packed-reference budget. Expected empty or tiny.
            var exportedSwiftNamesWithoutRows: Set<String> = []

            /// `false` when the image's export-trie enumeration yielded no
            /// entries at all (stripped-of-exports or static-style input) —
            /// then "not exported" is not a meaningful distinction and
            /// `isExported(name:)` answers `nil` rather than `false`.
            var hasExportInformation: Bool = false
        }

        let exportFacts: ExportFacts

        /// Whether `name` has an export-trie entry in this image:
        /// `true`/`false` per the trie, or `nil` when the image carries no
        /// export information at all (see `ExportFacts.hasExportInformation`).
        /// Only Swift names are recorded, matching the table's population —
        /// callers query with mangled member-symbol names.
        func isExported(name: String) -> Bool? {
            guard exportFacts.hasExportInformation else { return nil }
            if let row = symbolTable.row(forName: name) {
                let rowIndex = Int(row)
                return exportFacts.exportedRowBitmap[rowIndex >> 6] & (1 << UInt64(rowIndex & 63)) != 0
            }
            return exportFacts.exportedSwiftNamesWithoutRows.contains(name)
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

        fileprivate init(
            nodeStore: NodeStore,
            symbolTable: SymbolTable,
            rootNodeIndexByTableRow: [NodeStore.NodeIndex?],
            symbolRowsByOffset: [Int: SymbolRowBucket],
            exportFacts: ExportFacts,
            rowIndexes: consuming RowIndexes
        ) {
            self.nodeStore = nodeStore
            self.symbolTable = symbolTable
            self.rootNodeIndexByTableRow = rootNodeIndexByTableRow
            self.symbolRowsByOffset = symbolRowsByOffset
            self.exportFacts = exportFacts
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
            self.symbolRowsByKind = rowIndexes.symbolRowsByKind
            self.thunkAttributeMembersByKindAndTypeName = rowIndexes.thunkAttributeMembersByKindAndTypeName
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

        // MARK: Row materialization

        /// Rebuilds the `Symbol` for an offset-table row using the queried
        /// offset: raw and cache-adjusted keys share one canonical row, so
        /// the row's stored offset is not necessarily the queried one. The
        /// name is materialized fresh from the table's name source.
        fileprivate func symbol(atRow row: UInt32, offset queriedOffset: Int) -> Symbol {
            return Symbol(offset: queriedOffset, name: symbolTable.materializedName(atRow: row), isExternal: symbolTable.isExternal(atRow: row))
        }

        func demangledSymbol(atRow row: UInt32) -> DemangledSymbol? {
            guard let rootNodeIndex = rootNodeIndexByTableRow[Int(row)] else { return nil }
            return DemangledSymbol(symbolTable: symbolTable, symbolTableRow: row, demangledNode: nodeStore.reference(at: rootNodeIndex))
        }

        func demangledSymbols(atRows rows: some Sequence<UInt32>) -> [DemangledSymbol] {
            rows.compactMap { demangledSymbol(atRow: $0) }
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

        mutating func setGlobalSymbols(for result: ProcessGlobalSymbolResult) {
            globalSymbolRowsByKind[result.kind, default: []].append(result.symbolTableRow)
        }

        mutating func appendThunkAttributeMember(_ member: ThunkAttributeMember, forKind thunkKind: Node.Kind, typeName: String, typeNodeIndex: NodeStore.NodeIndex) {
            thunkAttributeMembersByKindAndTypeName[thunkKind, default: [:]][typeName, default: [:]][typeNodeIndex, default: []].append(member)
        }
    }

    public static let shared = SymbolIndexStore()

    private override init() {
        super.init()
    }

    public override func buildStorage<MachO: MachORepresentableWithCache>(for machO: MachO) -> Storage? {
        return buildStorageImpl(for: machO, progressContinuation: nil)
    }

    /// Batch boundary for the sweep's per-symbol demangling.
    ///
    /// `demangleAsNodeTransient` — like every `Demangling` entry point —
    /// probes the *calling* thread's remaining stack and moves the work to an
    /// 8MB worker when less than 2MB is left, blocking on a semaphore until
    /// that worker returns. Darwin gives every thread except the main one a
    /// 512KB stack, so on the Swift Concurrency cooperative worker or
    /// libdispatch worker a build runs on, that probe never passes: without a
    /// batch boundary each of a framework's hundreds of thousands of symbols
    /// pays its own thread round trip.
    ///
    /// One hop here puts the whole sweep on an 8MB thread, where the probe
    /// passes and every demangle inside runs inline — which is exactly what
    /// `withLargeStack` documents itself for ("indexing every symbol of a
    /// binary, say"). It is not a second guard: the probe and its 2MB floor
    /// are unchanged, this only stops the answer from being "no" every time.
    ///
    /// Wrapping the sweep's *call sites* instead would be a no-op — a hop that
    /// covers one demangle saves the one it replaces and nothing else. The
    /// saving is `(calls - 1)` hops, so the wrapper has to enclose the loop.
    private func buildStorageImpl<MachO: MachORepresentableWithCache>(
        for machO: MachO,
        progressContinuation: AsyncStream<Progress>.Continuation?
    ) -> Storage? {
        return StackSafeExecutor.withLargeStack {
            self.buildStorageSweep(for: machO, progressContinuation: progressContinuation)
        }
    }

    private func buildStorageSweep<MachO: MachORepresentableWithCache>(
        for machO: MachO,
        progressContinuation: AsyncStream<Progress>.Continuation?
    ) -> Storage? {
        // Reader split (proposal 0001): a MachOImage's symbol names already
        // live in the image's mmap'd string table, so its rows reference
        // those bytes in place — zero copies, zero retained strings — and
        // the Swift-symbol test runs on the raw bytes so non-Swift symbols
        // never materialize a name at all. Every other reader (MachOFile,
        // whose names are decoded per entry from the file) collects through
        // the generic leg below, whose Swift names are appended once into
        // the table's private byte buffer.
        let machOImage = machO as? MachOImage
        let mappedSymbols64 = machOImage?.symbols64
        let mappedSymbols32 = machOImage?.symbols32
        let mappedStringTableBase = mappedSymbols64.map { UnsafeRawPointer($0.stringBase) } ?? mappedSymbols32.map { UnsafeRawPointer($0.stringBase) }

        var tableBuilder = SymbolTableBuilder(mappedStringTableBase: mappedStringTableBase)
        var symbolRowsByOffset: [Int: SymbolRowBucket] = [:]

        // One offset legitimately maps to several rows — distinct symbol names
        // can share an address — so the bucket keeps list semantics (inline
        // for the dominant single-row case, spilling to an array only when a
        // second row actually lands; proposal 0003). The *same* row must not
        // be listed twice though, or every `for symbol in symbols` loop
        // visits it twice.
        //
        // A row repeats for two independent reasons, and each is headed off
        // without scanning the bucket:
        //
        // - Raw and canonical offsets coincide whenever there is nothing to
        //   adjust (a `MachOImage`, or a file at offset 0), which would make
        //   the second append a duplicate of the first. Comparing the two
        //   offsets settles it.
        // - Two symbol-table entries carrying the *same name* at the same
        //   address — aliases and weak definitions do occur in a symtab —
        //   fold onto one canonical row, so the second entry re-registers a
        //   row the first already put in that bucket. Only a row that already
        //   existed can be in a bucket at all: a freshly minted row index is
        //   `symbolTable.count`, strictly greater than every row issued so
        //   far, so no bucket can hold it. Checking `isNewRow` therefore
        //   settles this one too.
        //
        // Scanning the bucket instead would be O(bucket) on every symbol,
        // which is fine while buckets stay short but goes quadratic on a
        // degenerate address — offset 0, or a heavily aliased address in a
        // stripped or dyld-cache image — where thousands of distinct names
        // pile onto one offset. Those piles are exactly the case that must
        // stay cheap, and under `isNewRow` they never get scanned at all.
        func appendRow(_ row: UInt32, atOffset offset: Int, mayAlreadyBeListed: Bool) {
            if mayAlreadyBeListed, symbolRowsByOffset[offset]?.contains(row) == true {
                return
            }
            symbolRowsByOffset[offset, default: .empty].append(row)
        }

        func registerRow(_ row: UInt32, rawOffset: Int, canonicalOffset: Int, isNewRow: Bool) {
            appendRow(row, atOffset: rawOffset, mayAlreadyBeListed: !isNewRow)
            if canonicalOffset != rawOffset {
                appendRow(row, atOffset: canonicalOffset, mayAlreadyBeListed: !isNewRow)
            }
        }

        /// Mapped-name collection leg: iterates the image's own symbol
        /// sequence so each entry exposes `nameC` (a pointer into the
        /// mapped string table). The Swift-symbol test runs byte-level on
        /// that pointer; a `String` is materialized only for the symbols
        /// that pass it, and only as the build-time dedup key. An image's
        /// offsets need no cache adjustment (that path is `MachOFile`-only),
        /// so canonical == raw here.
        func collectMappedSymbolRows<MappedSymbols: Sequence<MachOImage.Symbol>>(_ mappedSymbols: MappedSymbols, stringBase: UnsafeRawPointer) {
            for symbol in mappedSymbols {
                guard nameBytesHaveSwiftManglingPrefix(symbol.nameC), !symbol.nlist.isExternal else { continue }
                // A `nil` row means the name's binary-supplied geometry
                // exceeds the packed budgets (malformed/hostile string
                // table) — skip the symbol instead of trapping (M3).
                guard let (row, isNewRow) = tableBuilder.canonicalRow(
                    forName: String(cString: symbol.nameC),
                    mappedNameByteOffset: UnsafeRawPointer(symbol.nameC) - stringBase,
                    nameByteLength: strlen(symbol.nameC),
                    canonicalOffset: symbol.offset,
                    isExternal: symbol.nlist.isExternal
                ) else { continue }
                registerRow(row, rawOffset: symbol.offset, canonicalOffset: symbol.offset, isNewRow: isNewRow)
            }
        }

        if let mappedSymbols64, let mappedStringTableBase {
            collectMappedSymbolRows(mappedSymbols64, stringBase: mappedStringTableBase)
        } else if let mappedSymbols32, let mappedStringTableBase {
            collectMappedSymbolRows(mappedSymbols32, stringBase: mappedStringTableBase)
        } else {
            for symbol in machO.symbols where symbol.name.isSwiftSymbol && !symbol.nlist.isExternal {
                let rawOffset = symbol.offset
                var canonicalOffset = rawOffset
                if let cache = machO.cache, rawOffset >= 0, machO is MachOFile {
                    canonicalOffset = rawOffset - cache.mainCacheHeader.sharedRegionStart.cast()
                }
                guard let (row, isNewRow) = tableBuilder.canonicalRow(forName: symbol.name, canonicalOffset: canonicalOffset, isExternal: symbol.nlist.isExternal) else { continue }
                registerRow(row, rawOffset: rawOffset, canonicalOffset: canonicalOffset, isNewRow: isNewRow)
            }
        }

        // The same single pass also collects the export facts (evolution
        // proposal 0008): every Swift trie name is recorded as exported —
        // by row when it has one, by name otherwise — because nothing else
        // remembers trie membership (the symtab legs above collect local
        // symbols only, and the row minting below is conditional). Bits are
        // set in the bitmap directly (row indices only grow, so the word
        // array grows monotonically; the final row count is settled at
        // freeze below, where the array is padded to full width).
        var sawAnyExportedSymbol = false
        var exportFacts = Storage.ExportFacts()
        func recordExportedRow(_ row: UInt32) {
            let wordIndex = Int(row) >> 6
            while exportFacts.exportedRowBitmap.count <= wordIndex {
                exportFacts.exportedRowBitmap.append(0)
            }
            exportFacts.exportedRowBitmap[wordIndex] |= 1 << UInt64(Int(row) & 63)
        }
        for exportedSymbol in machO.exportedSymbols {
            sawAnyExportedSymbol = true
            let name = exportedSymbol.name
            guard name.isSwiftSymbol else { continue }
            if let existingRow = tableBuilder.existingRow(forName: name) {
                recordExportedRow(existingRow)
            } else if let rawOffset = exportedSymbol.offset {
                var canonicalOffset = rawOffset
                if machO is MachOFile {
                    canonicalOffset += machO.startOffset
                }
                // The `existingRow` guard above means this name has no row
                // yet, so `canonicalRow` always mints one and the duplicate
                // check is never needed here. Export-trie names are decoded
                // strings with no home in the mapped string table, so they
                // take the private-buffer overload on every reader.
                guard let (row, isNewRow) = tableBuilder.canonicalRow(forName: name, canonicalOffset: canonicalOffset, isExternal: false) else {
                    // Refused by the packed-reference budget — the export
                    // fact still stands, it just has no row home.
                    exportFacts.exportedSwiftNamesWithoutRows.insert(name)
                    continue
                }
                registerRow(row, rawOffset: rawOffset, canonicalOffset: canonicalOffset, isNewRow: isNewRow)
                recordExportedRow(row)
            } else {
                // Offset-less trie entry (a re-export): exported, no row.
                exportFacts.exportedSwiftNamesWithoutRows.insert(name)
            }
        }
        exportFacts.hasExportInformation = sawAnyExportedSymbol

        // Freezing here drops the build-time dedup dictionary and sorts the
        // name-order permutation; the demangle sweep below reads names back
        // from the frozen table (a transient `String` per row — the
        // demangler's entry point takes a `String` until the upstream
        // byte-span entry lands, see proposal 0001's upstream-interface
        // section).
        let symbolTable = tableBuilder.freeze()

        // Row count is final after freeze (freezing sorts a permutation, it
        // never renumbers or adds rows); pad the bitmap to full width so
        // lookups never bounds-check.
        let exportedRowBitmapWordCount = (symbolTable.rowCount + 63) / 64
        while exportFacts.exportedRowBitmap.count < exportedRowBitmapWordCount {
            exportFacts.exportedRowBitmap.append(0)
        }

        // Single sequential sweep: demangle each symbol cache-free onto a
        // transient tree, classify on that tree, and intern the result into
        // the arena builder. Nothing touches the global `NodeCache` and no
        // class trees outlive the loop iteration (NodeStore migration plan,
        // Stage 1). Indexes accumulate directly in their final row-index
        // form (Stage 3), so `freeze()` is followed by a plain move into
        // `Storage`, not a conversion pass.
        let totalSymbolCount = symbolTable.rowCount

        var builder = NodeStoreBuilder()
        builder.reserveCapacity(expectedSymbolCount: totalSymbolCount)
        var rootNodeIndexByTableRow = [NodeStore.NodeIndex?](repeating: nil, count: totalSymbolCount)
        var rowIndexes = RowIndexes()

        for row in 0..<totalSymbolCount {
            if row % 500 == 0 {
                progressContinuation?.yield(Progress(currentCount: row, totalCount: totalSymbolCount))
            }

            let symbolTableRow = UInt32(row)
            guard let rootNode = try? demangleAsNodeTransient(symbolTable.materializedName(atRow: symbolTableRow)) else { continue }
            rootNodeIndexByTableRow[row] = builder.intern(rootNode)

            guard rootNode.isKind(of: .global), let node = rootNode.children.first else { continue }

            rowIndexes.appendSymbolRow(symbolTableRow, for: node.kind)

            if node.kind == .objCAttribute || node.kind == .nonObjCAttribute {
                if let extracted = processThunkAttributeSymbol(thunkKind: node.kind, rootNode: rootNode, builder: &builder) {
                    rowIndexes.appendThunkAttributeMember(extracted.member, forKind: node.kind, typeName: extracted.typeName, typeNodeIndex: extracted.typeNodeIndex)
                }
                continue
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
        progressContinuation?.yield(Progress(currentCount: totalSymbolCount, totalCount: totalSymbolCount))

        return Storage(
            nodeStore: builder.freeze(),
            symbolTable: symbolTable,
            rootNodeIndexByTableRow: rootNodeIndexByTableRow,
            symbolRowsByOffset: symbolRowsByOffset,
            exportFacts: exportFacts,
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

    /// Name-only lookup: first-wins across the (rare) same-named private
    /// types colliding on the stripped interface print. Prefer the
    /// node-taking overload whenever the caller holds the type's context
    /// node — the name alone cannot tell same-named private types apart.
    public func typeInfo<MachO: MachORepresentableWithCache>(for name: String, in machO: MachO) -> TypeInfo? {
        return storage(in: machO)?.typeInfoByName[name]?.values.first
    }

    /// Structural counterpart: resolves the `TypeInfo` of exactly the type
    /// whose context node matches `node`, so same-named private types each
    /// answer with their own kind.
    public func typeInfo<MachO: MachORepresentableWithCache>(for name: String, node: NodeReference, in machO: MachO) -> TypeInfo? {
        guard let storage = storage(in: machO) else { return nil }
        guard let typeInfoByTypeNodeIndex = storage.typeInfoByName[name] else { return nil }
        return typeInfoByTypeNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) })?.value
    }

    public func symbols<MachO: MachORepresentableWithCache>(of kinds: Node.Kind..., in machO: MachO) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { storage.demangledSymbols(atRows: storage.symbolRowsByKind[$0] ?? []) }.reduce(into: []) { $0 += $1 }
    }

    /// The number of symbols of `kinds` — O(1) per kind on the row index,
    /// for callers (the interface header's dispatch-thunk count) that need
    /// only the count and would otherwise materialize a `DemangledSymbol`
    /// array to throw it away.
    public func symbolCount<MachO: MachORepresentableWithCache>(of kinds: Node.Kind..., in machO: MachO) -> Int {
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
    public func isExported<MachO: MachORepresentableWithCache>(name: String, in machO: MachO) -> Bool? {
        guard let storage = storage(in: machO) else { return nil }
        return storage.isExported(name: name)
    }

    /// Whether the build sweep collected a symbol with exactly this name —
    /// presence in the symtab/trie population, regardless of export status.
    /// Backs the dump path's `@objc` exemption (evolution proposal 0008):
    /// an `@objc` member's ObjC entry point is its implementation name plus
    /// the `To` thunk suffix, so presence of that name identifies the
    /// member as objc_msgSend-reachable without demangling anything.
    public func containsSymbol<MachO: MachORepresentableWithCache>(named name: String, in machO: MachO) -> Bool {
        guard let storage = storage(in: machO) else { return false }
        return storage.symbolTable.row(forName: name) != nil
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
    public func isExportedIncludingDerivedSymbols<MachO: MachORepresentableWithCache>(name: String, in machO: MachO) -> Bool? {
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

    /// Returns the pre-extracted thunk-attribute members whose parent type
    /// name matches `typeName`. `thunkKind` is the demangler attribute marker
    /// kind (e.g. `.objCAttribute`, `.nonObjCAttribute`). Lookup is O(1) in the
    /// typeName bucket; no per-type scan of all thunk symbols is needed.
    /// Flattens every context-node bucket under the name — same-named private
    /// types are merged here; prefer the node-taking overload when the caller
    /// can supply the type's context node.
    public func thunkAttributeMembers<MachO: MachORepresentableWithCache>(
        of thunkKind: Node.Kind,
        for typeName: String,
        in machO: MachO
    ) -> [ThunkAttributeMember] {
        guard let membersByTypeNodeIndex = storage(in: machO)?.thunkAttributeMembersByKindAndTypeName[thunkKind]?[typeName] else { return [] }
        return membersByTypeNodeIndex.values.flatMap { $0 }
    }

    /// Structural counterpart: returns only the members whose parent context
    /// node matches `node`, so a same-named private sibling's `@objc` /
    /// `@nonobjc` thunks never stamp attributes onto this type's members.
    public func thunkAttributeMembers<MachO: MachORepresentableWithCache>(
        of thunkKind: Node.Kind,
        for typeName: String,
        node: NodeReference,
        in machO: MachO
    ) -> [ThunkAttributeMember] {
        guard let storage = storage(in: machO) else { return [] }
        guard let membersByTypeNodeIndex = storage.thunkAttributeMembersByKindAndTypeName[thunkKind]?[typeName] else { return [] }
        guard let matched = membersByTypeNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) }) else { return [] }
        return matched.value
    }

    /// Same lookup as the `NodeReference` overload, for callers holding an
    /// externally demangled `Node` (`MetadataReader.demangleContext` output in
    /// the dump path) rather than a store-backed reference.
    public func thunkAttributeMembers<MachO: MachORepresentableWithCache>(
        of thunkKind: Node.Kind,
        for typeName: String,
        node: Node,
        in machO: MachO
    ) -> [ThunkAttributeMember] {
        guard let storage = storage(in: machO) else { return [] }
        guard let membersByTypeNodeIndex = storage.thunkAttributeMembersByKindAndTypeName[thunkKind]?[typeName] else { return [] }
        guard let matched = membersByTypeNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) }) else { return [] }
        return matched.value
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

    /// Keyed on `StructuralNodeReferenceKey`, not a bare `NodeReference`: the
    /// keys are references into this image's frozen arena, so a caller probing
    /// the result with a tree it demangled itself would miss every entry under
    /// store-identity equality — silently, and with no compile error. The
    /// in-package consumer only iterates, but the vended contract has to hold
    /// for lookups too (`NodeStoreMigrationOpenIssues.md` item 3, reopened in the
    /// PR #103 round-three review and recorded in `ReviewAdjudications.md` A9).
    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., excluding names: borrowing Set<String>, in machO: MachO) -> OrderedDictionary<StructuralNodeReferenceKey, OrderedDictionary<MemberKind, [DemangledSymbol]>> {
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

    public func methodDescriptorMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, node: Node, in machO: MachO) -> [DemangledSymbol] {
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
    public func methodDescriptorMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, node: NodeReference, in machO: MachO) -> [DemangledSymbol] {
        guard let storage = storage(in: machO) else { return [] }
        return kinds.map { kind -> [DemangledSymbol] in
            guard let rowsByTypeNodeIndex = storage.methodDescriptorMemberSymbolRowsByKind[kind]?[name] else { return [] }
            guard let matched = rowsByTypeNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) }) else { return [] }
            return storage.demangledSymbols(atRows: matched.value)
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

    /// Structurally keyed for the same reason as `memberSymbols(of:excluding:in:)`
    /// above — and with the same precedent behind it: the single-item sibling
    /// `opaqueTypeDescriptorSymbol(for:)` was converted to a structural key after
    /// store-identity keys silently dropped the `override` keyword and the
    /// vtable-offset comments (the Stage 5a regression). This bulk form was left
    /// behind by that fix.
    public func allOpaqueTypeDescriptorSymbols<MachO: MachORepresentableWithCache>(in machO: MachO) -> OrderedDictionary<StructuralNodeReferenceKey, DemangledSymbol>? {
        guard let storage = storage(in: machO) else { return nil }
        var result: OrderedDictionary<StructuralNodeReferenceKey, DemangledSymbol> = [:]
        for (nodeIndex, row) in storage.opaqueTypeDescriptorSymbolRowByNodeIndex {
            guard let demangledSymbol = storage.demangledSymbol(atRow: row) else { continue }
            result[StructuralNodeReferenceKey(storage.nodeStore.reference(at: nodeIndex))] = demangledSymbol
        }
        return result
    }

    public func opaqueTypeDescriptorSymbol<MachO: MachORepresentableWithCache>(for node: Node, in machO: MachO) -> DemangledSymbol? {
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
