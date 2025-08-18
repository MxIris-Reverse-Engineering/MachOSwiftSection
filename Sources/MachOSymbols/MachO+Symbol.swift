import MachOKit
import MachOExtensions

extension MachORepresentableWithCache {
    package func symbols(offset: Int) -> MachOSymbols.Symbols? {
        return SymbolCache.shared.symbols(for: offset, in: self)
    }
}


extension MachORepresentable {
    package var swiftSymbols: [MachOSymbols.Symbol] {
        symbols.filter { $0.name.isSwiftSymbol }.map { .init(offset: $0.offset, stringValue: $0.name) }
    }
}
