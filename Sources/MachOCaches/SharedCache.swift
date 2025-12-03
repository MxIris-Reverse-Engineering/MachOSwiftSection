import Foundation
import MachOKit
import MachOExtensions
import Utilities
import SwiftStdlibToolbox

@_spi(Internals)
open class SharedCache<Entry>: @unchecked Sendable {
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
    private func createEntryIfNeeded(in machO: some MachORepresentableWithCache, isForced: Bool = false) -> Bool {
        guard isForced || (entryByIdentifier[machO.identifier] == nil) else { return false }
        entryByIdentifier[machO.identifier] = buildEntry(for: machO)
        return true
    }

    open func buildEntry(for machO: some MachORepresentableWithCache) -> Entry? {
        return nil
    }

    open func entry(in machO: some MachORepresentableWithCache) -> Entry? {
        createEntryIfNeeded(in: machO)
        if let cacheEntry = entryByIdentifier[machO.identifier] {
            return cacheEntry
        } else {
            return nil
        }
    }

    private var currentIdentifer: ObjectIdentifier {
        .init(Self.self)
    }

    @discardableResult
    private func createEntryIfNeeded(isForced: Bool = false) -> Bool {
        guard isForced || (entryByIdentifier[currentIdentifer] == nil) else { return false }
        entryByIdentifier[currentIdentifer] = buildEntry()
        return true
    }

    open func buildEntry() -> Entry? {
        return nil
    }

    open func entry() -> Entry? {
        createEntryIfNeeded()
        if let cacheEntry = entryByIdentifier[currentIdentifer] {
            return cacheEntry
        } else {
            return nil
        }
    }
}
