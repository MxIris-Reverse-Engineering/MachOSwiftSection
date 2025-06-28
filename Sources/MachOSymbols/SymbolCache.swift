import MachOKit
import MachOExtensions
import Demangle

package final class SymbolCache {
    package static let shared = SymbolCache()

    private let memoryPressureMonitor = MemoryPressureMonitor()

    private init() {
        memoryPressureMonitor.memoryWarningHandler = { [weak self] in
            self?.cacheEntryByIdentifier.removeAll()
        }

        memoryPressureMonitor.memoryCriticalHandler = { [weak self] in
            self?.cacheEntryByIdentifier.removeAll()
        }

        memoryPressureMonitor.startMonitoring()
    }

    private typealias CacheEntry = [Int: Symbol]

    private var cacheEntryByIdentifier: [AnyHashable: CacheEntry] = [:]

    @discardableResult
    package func createCacheIfNeeded<MachO: MachORepresentableWithCache>(in machO: MachO, isForced: Bool = false) -> Bool {
        guard isForced || (cacheEntryByIdentifier[machO.identifier]?.isEmpty ?? true) else { return false }
        var cacheEntry: CacheEntry = [:]

        for symbol in machO.symbols where symbol.name.isSwiftSymbol {
            var offset = symbol.offset
            cacheEntry[offset] = .init(offset: offset, stringValue: symbol.name)
            if let cache = machO.cache {
                offset -= cache.mainCacheHeader.sharedRegionStart.cast()
                cacheEntry[offset] = .init(offset: offset, stringValue: symbol.name)
            }
        }

        for exportedSymbol in machO.exportedSymbols where exportedSymbol.name.isSwiftSymbol {
            if var offset = exportedSymbol.offset {
                cacheEntry[offset] = .init(offset: offset, stringValue: exportedSymbol.name)
                offset += machO.startOffset
                cacheEntry[offset] = .init(offset: offset, stringValue: exportedSymbol.name)
            }
        }
        cacheEntryByIdentifier[machO.identifier] = cacheEntry
        return true
    }

    package func symbol<MachO: MachORepresentableWithCache>(for offset: Int, in machO: MachO) -> Symbol? {
        createCacheIfNeeded(in: machO)
        if let symbol = cacheEntryByIdentifier[machO.identifier, default: [:]][offset] {
            return symbol
        } else {
            return nil
        }
    }
}
