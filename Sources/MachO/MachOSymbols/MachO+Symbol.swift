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
    public var swiftSymbols: [MachOResolving.Symbol] {
        symbols.filter { $0.name.isSwiftSymbol }.map { .init(offset: $0.offset, name: $0.name) }
    }
}
