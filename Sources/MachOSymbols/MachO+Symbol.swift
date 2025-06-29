import MachOKit
import MachOExtensions

extension MachOFile {
    package func symbols(offset: Int) -> MachOSymbols.Symbols? {
        return SymbolCache.shared.symbols(for: offset, in: self)
    }
}

extension MachOImage {
    package func symbols(offset: Int) -> MachOSymbols.Symbols? {
        return SymbolCache.shared.symbols(for: offset, in: self)
    }
}
