import MachOKit
import MachOKitExtensions
import MachOResolving

extension MachORepresentableWithCache {
    /// Every symbol the image's index knows at `offset`, building the index
    /// on first use. `nil` when the image has no symbol at that offset (or
    /// no index could be built).
    public func symbols(offset: Int) -> MachOResolving.Symbols? {
        return SymbolIndexStore.shared.symbols(for: offset, in: self)
    }
}

extension MachORepresentable {
    /// The image's Swift symbols, each at the offset the symbol index files
    /// it under (see `SymbolValueOffsetConverter`). Debug-map entries are
    /// left out.
    public var swiftSymbols: [MachOResolving.Symbol] {
        let symbolValueOffsetConverter = (self as? MachOFile).map { SymbolValueOffsetConverter(for: $0) }
        return symbols.filter { $0.name.isSwiftSymbol && !$0.nlist.isDebuggingEntry }.map {
            .init(offset: symbolValueOffsetConverter?.offset(forSymbolValue: $0.offset) ?? $0.offset, name: $0.name)
        }
    }
}
