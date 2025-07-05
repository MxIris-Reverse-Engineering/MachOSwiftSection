import MachOKit
import MachOExtensions

extension MachORepresentableWithCache {
    package func symbols(offset: Int) -> MachOSymbols.Symbols? {
        return SymbolCache.shared.symbols(for: offset, in: self)
    }
}
