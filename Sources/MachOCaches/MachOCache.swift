import Foundation
import MachOKit
import MachOExtensions
import Utilities
import SwiftStdlibToolbox

@_spi(Internals)
open class MachOCache<Entry>: @unchecked Sendable {
    private let memoryPressureMonitor = MemoryPressureMonitor()

    package init() {
        memoryPressureMonitor.memoryWarningHandler = { [weak self] in
            self?.entryByIdentifier.removeAll()
        }

        memoryPressureMonitor.memoryCriticalHandler = { [weak self] in
            self?.entryByIdentifier.removeAll()
        }

        memoryPressureMonitor.startMonitoring()
    }

    @Mutex
    private var entryByIdentifier: [AnyHashable: Entry] = [:]

    @discardableResult
    private func createEntryIfNeeded<MachO: MachORepresentableWithCache>(in machO: MachO, isForced: Bool = false) -> Bool {
        guard isForced || (entryByIdentifier[machO.identifier] == nil) else { return false }
        entryByIdentifier[machO.identifier] = buildEntry(for: machO)
        return true
    }

    open func buildEntry<MachO: MachORepresentableWithCache>(for machO: MachO) -> Entry? {
        return nil
    }

    open func entry<MachO: MachORepresentableWithCache>(in machO: MachO) -> Entry? {
        createEntryIfNeeded(in: machO)
        if let cacheEntry = entryByIdentifier[machO.identifier] {
            return cacheEntry
        } else {
            return nil
        }
    }
    
    @discardableResult
    private func createEntryIfNeeded<MachO: MachORepresentableWithCache>(in machO: MachO, isForced: Bool = false) async -> Bool {
        guard isForced || (entryByIdentifier[machO.identifier] == nil) else { return false }
        entryByIdentifier[machO.identifier] = await buildEntry(for: machO)
        return true
    }
    
    open func buildEntry<MachO: MachORepresentableWithCache>(for machO: MachO) async -> Entry? {
        return nil
    }
    
    open func entry<MachO: MachORepresentableWithCache>(in machO: MachO) async -> Entry? {
        await createEntryIfNeeded(in: machO)
        if let cacheEntry = entryByIdentifier[machO.identifier] {
            return cacheEntry
        } else {
            return nil
        }
    }
}
