import MachOKit
import MachOExtensions
import Demangle
import OrderedCollections
import Utilities

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

    private typealias CacheEntry = OrderedDictionary<Int, [Symbol]>

    private var cacheEntryByIdentifier: [AnyHashable: CacheEntry] = [:]

    @discardableResult
    package func createCacheIfNeeded<MachO: MachORepresentableWithCache>(in machO: MachO, isForced: Bool = false) -> Bool {
        guard isForced || (cacheEntryByIdentifier[machO.identifier]?.isEmpty ?? true) else { return false }
        var cacheEntry: CacheEntry = [:]
        var cachedSymbols: Set<String> = []
        for symbol in machO.symbols where symbol.name.isSwiftSymbol {
            var offset = symbol.offset
            cacheEntry[offset, default: []].append(.init(offset: offset, stringValue: symbol.name))
            if let cache = machO.cache {
                offset -= cache.mainCacheHeader.sharedRegionStart.cast()
                cacheEntry[offset, default: []].append(.init(offset: offset, stringValue: symbol.name))
            }
            cachedSymbols.insert(symbol.name)
        }

        for exportedSymbol in machO.exportedSymbols where exportedSymbol.name.isSwiftSymbol && !cachedSymbols.contains(exportedSymbol.name) {
            if var offset = exportedSymbol.offset {
                cacheEntry[offset, default: []].append(.init(offset: offset, stringValue: exportedSymbol.name))
                offset += machO.startOffset
                cacheEntry[offset, default: []].append(.init(offset: offset, stringValue: exportedSymbol.name))
            }
        }
        cacheEntryByIdentifier[machO.identifier] = cacheEntry
        return true
    }

    package func symbols<MachO: MachORepresentableWithCache>(for offset: Int, in machO: MachO) -> Symbols? {
        createCacheIfNeeded(in: machO)
        if let symbols = cacheEntryByIdentifier[machO.identifier, default: [:]][offset], !symbols.isEmpty {
            return .init(offset: offset, symbols: symbols)
        } else {
            return nil
        }
    }
}
