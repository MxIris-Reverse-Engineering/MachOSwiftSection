import MachOKit
import MachOExtensions

extension MachOFile {
    package func findSymbol(offset: Int) -> MachOSymbol? {
        MachOSymbolCache.shared.createCacheIfNeeded(for: self)
        return MachOSymbolCache.shared.symbol(for: offset, in: self)
    }
}

extension MachOImage {
    package func findSymbol(offset: Int) -> MachOSymbol? {
        MachOSymbolCache.shared.createCacheIfNeeded(for: self)
        return MachOSymbolCache.shared.symbol(for: offset, in: self)
    }
}
