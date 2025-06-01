import MachOKit
import MachOExtensions
import AssociatedObject

private class SymbolCache {
    var symbolByOffset: [Int: UnsolvedSymbol] = [:]
}

extension MachOFile {
    @AssociatedObject(.retain(.nonatomic))
    private var symbolCache: SymbolCache = .init()

    private func buildSymbolByOffsetIfNeeded() {
        guard symbolCache.symbolByOffset.isEmpty else { return }
        guard let symbols64 else { return }
        var symbolByOffset: [Int: UnsolvedSymbol] = [:]
        for symbol in symbols64 where !symbol.name.isEmpty {
            var offset = symbol.offset
            if let cache {
                offset -= cache.mainCacheHeader.sharedRegionStart.cast()
            }
            symbolByOffset[offset] = .init(offset: offset, stringValue: symbol.name)
        }

        for exportedSymbol in exportedSymbols {
            if var offset = exportedSymbol.offset {
                if let cache {
                    offset -= cache.mainCacheHeader.sharedRegionStart.cast()
                }
                symbolByOffset[offset] = .init(offset: offset, stringValue: exportedSymbol.name)
            }
        }
        symbolCache.symbolByOffset = symbolByOffset
    }

    package func findSymbol(offset: Int) -> UnsolvedSymbol? {
        buildSymbolByOffsetIfNeeded()
        return symbolCache.symbolByOffset[offset]
    }
}


