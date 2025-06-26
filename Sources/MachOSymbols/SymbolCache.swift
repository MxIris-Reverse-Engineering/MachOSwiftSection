import MachOKit
import MachOExtensions
import Demangle

enum MachOTargetIdentifier: Hashable {
    case image(UnsafeRawPointer)
    case file(String)
}

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

    private var cacheEntryByIdentifier: [MachOTargetIdentifier: CacheEntry] = [:]

    @discardableResult
    package func createCacheIfNeeded(for machOImage: MachOImage, isForced: Bool = false) -> Bool {
        let identifier = MachOTargetIdentifier.image(machOImage.ptr)
        return createCacheIfNeeded(for: identifier, in: machOImage, isForced: isForced)
    }

    @discardableResult
    package func createCacheIfNeeded(for machOFile: MachOFile, isForced: Bool = false) -> Bool {
        let identifier = MachOTargetIdentifier.file(machOFile.imagePath)
        return createCacheIfNeeded(for: identifier, in: machOFile, isForced: isForced)
    }

    @discardableResult
    private func createCacheIfNeeded<MachO: MachORepresentableWithCache>(for identifier: MachOTargetIdentifier, in machO: MachO, isForced: Bool = false) -> Bool {
        guard isForced || (cacheEntryByIdentifier[identifier]?.isEmpty ?? true) else { return false }
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
        cacheEntryByIdentifier[identifier] = cacheEntry
        return true
    }

    package func removeCache(for machOImage: MachOImage) {
        let identifier = MachOTargetIdentifier.image(machOImage.ptr)
        removeCache(for: identifier)
    }

    package func removeCache(for machOFile: MachOFile) {
        let identifier = MachOTargetIdentifier.file(machOFile.imagePath)
        removeCache(for: identifier)
    }

    private func removeCache(for identifier: MachOTargetIdentifier) {
        cacheEntryByIdentifier.removeValue(forKey: identifier)
    }

    package func symbol(for offset: Int, in machOImage: MachOImage) -> Symbol? {
        let identifier = MachOTargetIdentifier.image(machOImage.ptr)
        return symbol(for: offset, with: identifier, in: machOImage)
    }

    package func symbol(for offset: Int, in machOFile: MachOFile) -> Symbol? {
        let identifier = MachOTargetIdentifier.file(machOFile.imagePath)
        return symbol(for: offset, with: identifier, in: machOFile)
    }

    private func symbol<MachO: MachORepresentableWithCache>(for offset: Int, with identifier: MachOTargetIdentifier, in machO: MachO) -> Symbol? {
        if let symbol = cacheEntryByIdentifier[identifier, default: [:]][offset] {
            return symbol
        } else {
            return nil
        }
    }
}
