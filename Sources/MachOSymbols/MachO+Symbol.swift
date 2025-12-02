import MachOKit
import MachOExtensions

extension MachORepresentableWithCache {
    public func symbols(offset: Int) -> MachOSymbols.Symbols? {
        return SymbolIndexStore.shared.symbols(for: offset, in: self)
    }

    public func symbols(offset: Int) async -> MachOSymbols.Symbols? {
        return SymbolIndexStore.shared.symbols(for: offset, in: self)
    }
}

extension MachORepresentable {
    public var swiftSymbols: [MachOSymbols.Symbol] {
        symbols.filter { $0.name.isSwiftSymbol }.map { .init(offset: $0.offset, name: $0.name) }
    }
}
