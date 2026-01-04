import Foundation
import MachOKit
import MachOExtensions
import Utilities
import SwiftStdlibToolbox

@_spi(Internals)
open class SharedCache<Storage>: @unchecked Sendable {
    private let memoryPressureMonitor = MemoryPressureMonitor()

    package init() {
        memoryPressureMonitor.memoryWarningHandler = { [weak self] in
            self?.storageByIdentifier.removeAll()
        }

        memoryPressureMonitor.memoryCriticalHandler = { [weak self] in
            self?.storageByIdentifier.removeAll()
        }

        memoryPressureMonitor.startMonitoring()
    }

    @Mutex
    private var storageByIdentifier: [AnyHashable: Storage] = [:]

    @discardableResult
    private func createStorageIfNeeded(in machO: some MachORepresentableWithCache, isForced: Bool = false) -> Bool {
        guard isForced || (storageByIdentifier[machO.identifier] == nil) else { return false }
        storageByIdentifier[machO.identifier] = buildStorage(for: machO)
        return true
    }

    open func buildStorage(for machO: some MachORepresentableWithCache) -> Storage? {
        return nil
    }

    open func storage(in machO: some MachORepresentableWithCache) -> Storage? {
        createStorageIfNeeded(in: machO)
        if let cacheEntry = storageByIdentifier[machO.identifier] {
            return cacheEntry
        } else {
            return nil
        }
    }

    private var currentIdentifer: ObjectIdentifier {
        .init(Self.self)
    }

    @discardableResult
    private func createStorageIfNeeded(isForced: Bool = false) -> Bool {
        guard isForced || (storageByIdentifier[currentIdentifer] == nil) else { return false }
        storageByIdentifier[currentIdentifer] = buildStorage()
        return true
    }

    open func buildStorage() -> Storage? {
        return nil
    }

    open func storage() -> Storage? {
        createStorageIfNeeded()
        if let cacheEntry = storageByIdentifier[currentIdentifer] {
            return cacheEntry
        } else {
            return nil
        }
    }
}
