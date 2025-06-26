import MachOKit
import MachOExtensions

extension MachOFile {
    package func findSymbol(offset: Int) -> MachOSymbols.Symbol? {
        SymbolCache.shared.createCacheIfNeeded(for: self)
        return SymbolCache.shared.symbol(for: offset, in: self)
    }
}

extension MachOImage {
    package func findSymbol(offset: Int) -> MachOSymbols.Symbol? {
        SymbolCache.shared.createCacheIfNeeded(for: self)
        return SymbolCache.shared.symbol(for: offset, in: self)
    }
}
