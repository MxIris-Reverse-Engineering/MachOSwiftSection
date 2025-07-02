import Foundation
import MachOKit
import Utilities

open class MachOCache<Entry> {
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
    
    private var cacheEntryByIdentifier: [AnyHashable: Entry] = [:]
    
}
