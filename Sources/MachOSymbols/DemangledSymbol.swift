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

    public subscript<Value>(dynamicMember keyPath: KeyPath<Symbol, Value>) -> Value {
        return symbol[keyPath: keyPath]
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<NodeReference, Value>) -> Value {
        return demangledNode[keyPath: keyPath]
    }
}
