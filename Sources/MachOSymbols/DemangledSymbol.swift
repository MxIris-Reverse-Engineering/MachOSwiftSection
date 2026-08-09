import Demangling

/// A symbol paired with the handle of its demangled tree.
///
/// Compact by construction (NodeStore migration, Stage 3): instead of an
/// inline `Symbol` copy the value stores a row index into the per-image
/// symbol table, so the hundreds of thousands of `DemangledSymbol` values
/// vended by `SymbolIndexStore` share one `SymbolTable` and stay at
/// 32 bytes each (table reference + row + `NodeReference`). Since evolution
/// proposal 0001 the shared table holds no name `String`s either — `symbol`
/// materializes its name on demand from the table's name source.
@dynamicMemberLookup
public struct DemangledSymbol: Sendable {
    private let symbolTable: SymbolTable

    private let symbolTableRow: UInt32

    public let demangledNode: NodeReference

    public var symbol: Symbol {
        symbolTable.symbol(atRow: symbolTableRow)
    }

    // Concrete fast paths for the members the dynamic-member subscript would
    // otherwise serve by building a whole `Symbol` — which materializes the
    // name `String` even for a plain `offset` read now that names are
    // offset-ized. Values are identical to the key-path route.

    public var offset: Int {
        symbolTable.canonicalOffset(atRow: symbolTableRow)
    }

    public var isExternal: Bool {
        symbolTable.isExternal(atRow: symbolTableRow)
    }

    public var name: String {
        symbolTable.materializedName(atRow: symbolTableRow)
    }

    /// Wraps a standalone symbol in a single-row table. `SymbolIndexStore`
    /// vends values through the shared-table initializer instead.
    ///
    /// The one-row table is a deliberate trade, not an oversight: storing
    /// the `Symbol` inline instead (a two-case payload enum) would avoid this
    /// allocation, but `Symbol` is itself 32 bytes, so every `DemangledSymbol`
    /// — including the hundreds of thousands vended through the shared table —
    /// would grow past the 32-byte budget `compactValueLayouts` pins. Paying a
    /// small allocation on the rarer standalone path is cheaper than widening
    /// the common one.
    public init(symbol: Symbol, demangledNode: NodeReference) {
        self.symbolTable = SymbolTable(standaloneSymbol: symbol)
        self.symbolTableRow = 0
        self.demangledNode = demangledNode
    }

    init(symbolTable: SymbolTable, symbolTableRow: UInt32, demangledNode: NodeReference) {
        self.symbolTable = symbolTable
        self.symbolTableRow = symbolTableRow
        self.demangledNode = demangledNode
    }

    /// Copies the referenced row into a standalone one-row table, so this
    /// value stops retaining the shared per-image table.
    ///
    /// The shared table is the right trade for the hundreds of thousands of
    /// values a query vends and then drops — they cost 32 bytes each instead
    /// of carrying a `Symbol` copy. It is the wrong trade for the handful that
    /// outlive the query by being stored in the declaration model
    /// (`Accessor.symbol`, `FunctionDefinition.symbol`,
    /// `TypeDefinition.deallocatorSymbol` / `destructorSymbol`): a single one
    /// of those pins the entire table plus every name byte in it — and, for a
    /// `MachOImage` table, keeps vend-time reads against the loaded image's
    /// string table alive — which is what
    /// `SwiftDeclarationIndexer.removeSubIndexer(_:)` exists to reclaim.
    /// Measured on SwiftUI (iOS 18.5): 9,872 stored values referenced 9,506
    /// distinct rows — 5.1% of a 185,988-row table — so detaching them trades
    /// roughly 0.6 MB of small allocations for the whole table's retention.
    ///
    /// What detaches is the SYMBOL-TABLE layer only (rows + name bytes and,
    /// for an image table, its tie to the loaded image's mapped string
    /// table). `demangledNode` deliberately keeps referencing the per-image
    /// node store: the owning definition's `node` field is the same
    /// reference into the same store (the intended per-image recycling
    /// model — a live definition keeps its store alive), so copying the
    /// tree out here would reclaim nothing while the model lives and would
    /// only add an allocation per stored symbol.
    /// `SymbolTableRetentionTests` pins both layers of this contract.
    ///
    /// Call this when storing a value into a long-lived declaration, not on
    /// the query path.
    public func detachedFromSharedTable() -> DemangledSymbol {
        return DemangledSymbol(symbol: symbol, demangledNode: demangledNode)
    }

    /// Rows in the table backing this value: the whole per-image table for a
    /// value straight off a query, `1` once ``detachedFromSharedTable()`` has
    /// copied its row out. Exposed so the retention regression test can tell
    /// the two apart without reaching into private storage.
    package var retainedSymbolTableRowCount: Int {
        return symbolTable.rowCount
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<Symbol, Value>) -> Value {
        return symbol[keyPath: keyPath]
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<NodeReference, Value>) -> Value {
        return demangledNode[keyPath: keyPath]
    }
}
