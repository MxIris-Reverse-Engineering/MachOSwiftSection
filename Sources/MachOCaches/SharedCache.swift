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

    open func buildStorage(for machO: some MachORepresentableWithCache) -> Storage? {
        return nil
    }

    open func storage<MachO: MachORepresentableWithCache>(in machO: MachO) -> Storage? {
        return storage(in: machO) { machO in
            buildStorage(for: machO)
        }
    }

    /// Atomic get-or-build with a caller-provided build closure.
    ///
    /// Unlike `storage(in:)` which uses the overridden `buildStorage(for:)`, this variant
    /// lets the caller inject a custom build closure that can capture per-call context
    /// (progress continuations, options, etc). The per-call context flows through closure
    /// capture, never through shared instance state, so concurrent calls cannot interfere.
    ///
    /// The entire check-build-insert runs inside a single `withLockUnchecked` critical
    /// section, guaranteeing atomicity independent of the `_modify` accessor that
    /// `@Mutex` may or may not generate for the underlying property.
    public func storage<MachO: MachORepresentableWithCache>(
        in machO: MachO,
        buildUsing build: (MachO) -> Storage?
    ) -> Storage? {
        return _storageByIdentifier.withLockUnchecked { dict -> Storage? in
            let key: AnyHashable = machO.identifier
            if let existing = dict[key] { return existing }
            guard let new = build(machO) else { return nil }
            dict[key] = new
            return new
        }
    }

    private var currentIdentifer: ObjectIdentifier {
        .init(Self.self)
    }

    open func buildStorage() -> Storage? {
        return nil
    }

    open func storage() -> Storage? {
        return _storageByIdentifier.withLockUnchecked { dict -> Storage? in
            let key: AnyHashable = currentIdentifer
            if let existing = dict[key] { return existing }
            guard let new = buildStorage() else { return nil }
            dict[key] = new
            return new
        }
    }
}
