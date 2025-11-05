//import MachOKit
//import MachOExtensions
//import Demangling
//import OrderedCollections
//import Utilities
//@_spi(Internals) import MachOCaches
//import SwiftStdlibToolbox
//
//package final class SymbolCache: MachOCache<SymbolCache.Entry>, @unchecked Sendable {
//    package static let shared = SymbolCache()
//
//    private override init() { super.init() }
//
//    package final class Entry {
//        fileprivate var symbolsByOffset: OrderedDictionary<Int, [Symbol]> = [:]
//        fileprivate var demangledNodeBySymbol: [Symbol: Node] = [:]
//    }
//
//    package override func buildEntry<MachO>(for machO: MachO) -> Entry? where MachO: MachORepresentableWithCache {
//        let cacheEntry = Entry()
//        var cachedSymbols: Set<String> = []
//        var symbolsByOffset: OrderedDictionary<Int, [Symbol]> = [:]
//        for symbol in machO.symbols where symbol.name.isSwiftSymbol {
//            var offset = symbol.offset
//            symbolsByOffset[offset, default: []].append(.init(offset: offset, name: symbol.name, nlist: symbol.nlist))
//            if let cache = machO.cache {
//                offset -= cache.mainCacheHeader.sharedRegionStart.cast()
//                symbolsByOffset[offset, default: []].append(.init(offset: offset, name: symbol.name, nlist: symbol.nlist))
//            }
//            cachedSymbols.insert(symbol.name)
//        }
//
//        for exportedSymbol in machO.exportedSymbols where exportedSymbol.name.isSwiftSymbol && !cachedSymbols.contains(exportedSymbol.name) {
//            if var offset = exportedSymbol.offset {
//                symbolsByOffset[offset, default: []].append(.init(offset: offset, name: exportedSymbol.name))
//                offset += machO.startOffset
//                symbolsByOffset[offset, default: []].append(.init(offset: offset, name: exportedSymbol.name))
//            }
//        }
//        cacheEntry.symbolsByOffset = symbolsByOffset
//        return cacheEntry
//    }
//
//    package func symbols<MachO: MachORepresentableWithCache>(for offset: Int, in machO: MachO) -> Symbols? {
//        if let symbols = entry(in: machO)?.symbolsByOffset[offset], !symbols.isEmpty {
//            return .init(offset: offset, symbols: symbols)
//        } else {
//            return nil
//        }
//    }
//
//    package func demangledNode<MachO: MachORepresentableWithCache>(for symbol: Symbol, in machO: MachO) -> Node? {
//        guard let cacheEntry = entry(in: machO) else { return nil }
//        if let node = cacheEntry.demangledNodeBySymbol[symbol] {
//            return node
//        } else if let node = try? demangleAsNode(symbol.name) {
//            cacheEntry.demangledNodeBySymbol[symbol] = node
//            return node
//        } else {
//            return nil
//        }
//    }
//    
//    package func prepare<MachO: MachORepresentableWithCache>(in machO: MachO) {
//        _ = entry(in: machO)
//    }
//}
