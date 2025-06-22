import MachOKit
import MachOExtensions

class MachOSymbolCache {
    static let shared = MachOSymbolCache()

    private let memoryPressureMonitor = MemoryPressureMonitor()

    private init() {
        memoryPressureMonitor.memoryWarningHandler = { [weak self] in
            self?.entryByIdentifier.removeAll()
        }

        memoryPressureMonitor.memoryCriticalHandler = { [weak self] in
            self?.entryByIdentifier.removeAll()
        }

        memoryPressureMonitor.startMonitoring()
    }

    private enum CacheIdentifier: Hashable {
        case image(UnsafeRawPointer)
        case file(String)
    }

    private typealias CacheEntry = [Int: MachOSymbol]

    private var entryByIdentifier: [CacheIdentifier: CacheEntry] = [:]

    @discardableResult
    private func createCacheIfNeeded<MachO: MachORepresentableWithCache>(for identifier: CacheIdentifier, in machO: MachO, isForced: Bool = false) -> Bool {
        guard isForced || (entryByIdentifier[identifier]?.isEmpty ?? true) else { return false }
        guard let symbols64 = machO.symbols64 else { return false }
        var cacheEntry: CacheEntry = [:]
        for symbol in symbols64 where !symbol.name.isEmpty {
            var offset = symbol.offset
            cacheEntry[offset] = .init(offset: offset, stringValue: symbol.name)
            if let cache = machO.cache {
                offset -= cache.mainCacheHeader.sharedRegionStart.cast()
                cacheEntry[offset] = .init(offset: offset, stringValue: symbol.name)
            }
        }

        for exportedSymbol in machO.exportedSymbols {
            if var offset = exportedSymbol.offset {
                cacheEntry[offset] = .init(offset: offset, stringValue: exportedSymbol.name)
                offset += machO.startOffset
                cacheEntry[offset] = .init(offset: offset, stringValue: exportedSymbol.name)
            }
        }
        entryByIdentifier[identifier] = cacheEntry
        return true
    }

    private func removeCache(for identifier: CacheIdentifier) {
        entryByIdentifier.removeValue(forKey: identifier)
    }

    func removeCache(for machOImage: MachOImage) {
        let identifier = CacheIdentifier.image(machOImage.ptr)
        removeCache(for: identifier)
    }

    func removeCache(for machOFile: MachOFile) {
        let identifier = CacheIdentifier.file(machOFile.imagePath)
        removeCache(for: identifier)
    }

    @discardableResult
    func createCacheIfNeeded(for machOImage: MachOImage, isForced: Bool = false) -> Bool {
        let identifier = CacheIdentifier.image(machOImage.ptr)
        return createCacheIfNeeded(for: identifier, in: machOImage, isForced: isForced)
    }

    @discardableResult
    func createCacheIfNeeded(for machOFile: MachOFile, isForced: Bool = false) -> Bool {
        let identifier = CacheIdentifier.file(machOFile.imagePath)
        return createCacheIfNeeded(for: identifier, in: machOFile, isForced: isForced)
    }

    func symbol(for offset: Int, in machOImage: MachOImage) -> MachOSymbol? {
        let identifier = CacheIdentifier.image(machOImage.ptr)
        return symbol(for: offset, with: identifier, in: machOImage)
    }

    func symbol(for offset: Int, in machOFile: MachOFile) -> MachOSymbol? {
        let identifier = CacheIdentifier.file(machOFile.imagePath)
        return symbol(for: offset, with: identifier, in: machOFile)
    }

    private func symbol<MachO: MachORepresentableWithCache>(for offset: Int, with identifier: CacheIdentifier, in machO: MachO) -> MachOSymbol? {
        if let symbol = entryByIdentifier[identifier, default: [:]][offset] {
            return symbol
        } else {
            return nil
        }
    }
}
