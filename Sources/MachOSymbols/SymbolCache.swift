import MachOKit
import MachOExtensions
import Demangle
import OrderedCollections
import Utilities
@_spi(Private) import MachOCaches

package final class SymbolCache: MachOCache<SymbolCache.Entry> {
    package static let shared = SymbolCache()

    private override init() { super.init() }

    package final class Entry {
        fileprivate var symbolsByOffset: OrderedDictionary<Int, [Symbol]> = [:]
        fileprivate var demangledNodeBySymbol: [Symbol: Node] = [:]
    }

    package override func buildEntry<MachO>(for machO: MachO) -> Entry? where MachO: MachORepresentableWithCache {
        let cacheEntry = Entry()
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

        return cacheEntry
    }

    package func symbols<MachO: MachORepresentableWithCache>(for offset: Int, in machO: MachO) -> Symbols? {
        if let symbols = entry(in: machO)?.symbolsByOffset[offset], !symbols.isEmpty {
            return .init(offset: offset, symbols: symbols)
        } else {
            return nil
        }
    }

    package func demangledNode<MachO: MachORepresentableWithCache>(for symbol: Symbol, in machO: MachO) -> Node? {
        guard let cacheEntry = entry(in: machO) else { return nil }
        if let node = cacheEntry.demangledNodeBySymbol[symbol] {
            return node
        } else if let node = try? demangleAsNode(symbol.stringValue) {
            cacheEntry.demangledNodeBySymbol[symbol] = node
            return node
        } else {
            return nil
        }
    }
}
