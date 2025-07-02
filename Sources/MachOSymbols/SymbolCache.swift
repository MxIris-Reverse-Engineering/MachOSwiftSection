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

    private struct CacheEntry {
        var isLoaded: Bool = false
        var symbolsByOffset: OrderedDictionary<Int, [Symbol]> = [:]
        var demangledNodeBySymbol: [Symbol: Node] = [:]
    }

    private var cacheEntryByIdentifier: [AnyHashable: CacheEntry] = [:]

    @discardableResult
    package func createCacheIfNeeded<MachO: MachORepresentableWithCache>(in machO: MachO, isForced: Bool = false) -> Bool {
        guard isForced || ((cacheEntryByIdentifier[machO.identifier].map(\.isLoaded) ?? false) == false) else { return false }
        var cacheEntry: CacheEntry = .init()
        var cachedSymbols: Set<String> = []
        for symbol in machO.symbols where symbol.name.isSwiftSymbol {
            var offset = symbol.offset
            cacheEntry.symbolsByOffset[offset, default: []].append(.init(offset: offset, stringValue: symbol.name))
            if let cache = machO.cache {
                offset -= cache.mainCacheHeader.sharedRegionStart.cast()
                cacheEntry.symbolsByOffset[offset, default: []].append(.init(offset: offset, stringValue: symbol.name))
            }
            cachedSymbols.insert(symbol.name)
        }

        for exportedSymbol in machO.exportedSymbols where exportedSymbol.name.isSwiftSymbol && !cachedSymbols.contains(exportedSymbol.name) {
            if var offset = exportedSymbol.offset {
                cacheEntry.symbolsByOffset[offset, default: []].append(.init(offset: offset, stringValue: exportedSymbol.name))
                offset += machO.startOffset
                cacheEntry.symbolsByOffset[offset, default: []].append(.init(offset: offset, stringValue: exportedSymbol.name))
            }
        }
        
//        for symbol in cacheEntry.symbolsByOffset.values.flatMap({ $0 }) {
//            do {
//                let node = try demangleAsNode(symbol.stringValue)
//                cacheEntry.demangledNodeBySymbol[symbol] = node
//            } catch {
//                print(error)
//            }
//        }
        
        cacheEntry.isLoaded = true
        cacheEntryByIdentifier[machO.identifier] = cacheEntry
        return true
    }

    package func symbols<MachO: MachORepresentableWithCache>(for offset: Int, in machO: MachO) -> Symbols? {
        createCacheIfNeeded(in: machO)
        if let symbols = cacheEntryByIdentifier[machO.identifier]?.symbolsByOffset[offset], !symbols.isEmpty {
            return .init(offset: offset, symbols: symbols)
        } else {
            return nil
        }
    }
    
    package func demangledNode<MachO: MachORepresentableWithCache>(for symbol: Symbol, in machO: MachO) -> Node? {
        createCacheIfNeeded(in: machO)
        guard var cacheEntry = cacheEntryByIdentifier[machO.identifier] else { return nil }
        if let node = cacheEntry.demangledNodeBySymbol[symbol] {
            return node
        } else if let node = try? demangleAsNode(symbol.stringValue) {
            cacheEntry.demangledNodeBySymbol[symbol] = node
            cacheEntryByIdentifier[machO.identifier] = cacheEntry
            return node
        } else {
            return nil
        }
    }
}
