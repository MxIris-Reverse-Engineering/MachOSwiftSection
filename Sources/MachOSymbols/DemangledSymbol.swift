import Demangling

/// A symbol paired with the handle of its demangled tree.
///
/// Compact by construction (NodeStore migration, Stage 3): instead of an
/// inline `Symbol` copy the value stores a row index into the per-image flat
/// symbol table, so the hundreds of thousands of `DemangledSymbol` values
/// vended by `SymbolIndexStore` share one `[Symbol]` buffer and stay at
/// 32 bytes each (table reference + row + `NodeReference`).
@dynamicMemberLookup
public struct DemangledSymbol: Sendable {
    private let symbolTable: [Symbol]

    private let symbolTableRow: UInt32

    public let demangledNode: NodeReference

    public var symbol: Symbol {
        symbolTable[Int(symbolTableRow)]
    }

    /// Wraps a standalone symbol in a single-row table. `SymbolIndexStore`
    /// vends values through the shared-table initializer instead.
    ///
    /// The one-element array is a deliberate trade, not an oversight: storing
    /// the `Symbol` inline instead (a two-case payload enum) would avoid this
    /// allocation, but `Symbol` is itself 32 bytes, so every `DemangledSymbol`
    /// — including the hundreds of thousands vended through the shared table —
    /// would grow past the 32-byte budget `compactValueLayouts` pins. Paying a
    /// small allocation on the rarer standalone path is cheaper than widening
    /// the common one.
    public init(symbol: Symbol, demangledNode: NodeReference) {
        self.symbolTable = [symbol]
        self.symbolTableRow = 0
        self.demangledNode = demangledNode
    }

    init(symbolTable: [Symbol], symbolTableRow: UInt32, demangledNode: NodeReference) {
        self.symbolTable = symbolTable
        self.symbolTableRow = symbolTableRow
        self.demangledNode = demangledNode
    }

    /// Copies the referenced row into a standalone one-row table, so this
    /// value stops retaining the shared per-image buffer.
    ///
    /// The shared table is the right trade for the hundreds of thousands of
    /// values a query vends and then drops — they cost 32 bytes each instead
    /// of carrying a `Symbol` copy. It is the wrong trade for the handful that
    /// outlive the query by being stored in the declaration model
    /// (`Accessor.symbol`, `FunctionDefinition.symbol`,
    /// `TypeDefinition.deallocatorSymbol` / `destructorSymbol`): a single one
    /// of those pins the entire table plus every mangled name in it, which is
    /// what `SwiftDeclarationIndexer.removeSubIndexer(_:)` exists to reclaim.
    /// Measured on SwiftUI (iOS 18.5): 9,872 stored values referenced 9,506
    /// distinct rows — 5.1% of a 185,988-row table — so detaching them trades
    /// roughly 0.6 MB of small allocations for about 19.9 MB of retention.
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
        return symbolTable.count
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<Symbol, Value>) -> Value {
        return symbol[keyPath: keyPath]
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<NodeReference, Value>) -> Value {
        return demangledNode[keyPath: keyPath]
    }
}
