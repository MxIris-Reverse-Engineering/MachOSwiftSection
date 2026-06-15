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

    /// Per-key state: a finished build (`completed`) or an in-flight build
    /// that other callers can join via the promise (`inFlight`). The
    /// in-flight marker lets concurrent callers for the same key share one
    /// build instead of serializing against the cache lock for the build's
    /// entire duration.
    private enum Entry {
        case completed(Storage)
        case inFlight(SharedCacheBuildPromise<Storage>)
    }

    @Mutex
    private var storageByIdentifier: [AnyHashable: Entry] = [:]

    /// Routing decision the cache lock makes on behalf of `storage(...)`:
    /// either return a cached value, await someone else's in-flight build,
    /// or run the build ourselves under the freshly-installed promise.
    private enum Outcome {
        case completed(Storage)
        case wait(SharedCacheBuildPromise<Storage>)
        case build(SharedCacheBuildPromise<Storage>)
    }

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
    /// Unlike `storage(in:)` which uses the overridden `buildStorage(for:)`,
    /// this variant lets the caller inject a custom build closure that can
    /// capture per-call context (progress continuations, options, etc.). The
    /// per-call context flows through closure capture, never through shared
    /// instance state, so concurrent calls cannot interfere.
    ///
    /// The cache lock is held only long enough to look up the key and either
    /// hand back a finished value, attach to an in-flight build, or install
    /// our own in-flight marker. The build closure itself executes
    /// **outside** the lock, so two callers building entries for different
    /// Mach-O identifiers run in parallel; two callers building entries for
    /// the same identifier de-duplicate via the in-flight promise.
    public func storage<MachO: MachORepresentableWithCache>(
        in machO: MachO,
        buildUsing build: (MachO) -> Storage?
    ) -> Storage? {
        let key: AnyHashable = machO.identifier
        return resolve(key: key) { build(machO) }
    }

    private var currentIdentifer: ObjectIdentifier {
        .init(Self.self)
    }

    open func buildStorage() -> Storage? {
        return nil
    }

    open func storage() -> Storage? {
        let key: AnyHashable = currentIdentifer
        return resolve(key: key) { buildStorage() }
    }

    /// Returns `true` when a finished build is already cached for `machO`'s
    /// identifier. In-flight builds count as **not** cached: a caller that
    /// observes `false` here, then runs ``storage(in:)``, may end up sharing
    /// an existing in-flight build with another caller — but from the
    /// "self-triggered" perspective (see ``SwiftDeclarationIndexer``) that is
    /// still cooperative ownership, not sole ownership, so reporting `true`
    /// for in-flight would mislead the bookkeeping.
    public func contains<MachO: MachORepresentableWithCache>(in machO: MachO) -> Bool {
        return contains(key: machO.identifier)
    }

    /// Type-keyed variant matching ``storage()``.
    public func contains() -> Bool {
        return contains(key: currentIdentifer)
    }

    private func contains(key: AnyHashable) -> Bool {
        _storageByIdentifier.withLockUnchecked { dict in
            if case .completed = dict[key] {
                return true
            }
            return false
        }
    }

    /// Drops the cached entry for `machO`'s identifier so the next
    /// ``storage(in:)`` call rebuilds from scratch. In-flight builds are left
    /// alone: their waiters still need the promise to settle, and the next
    /// completed result simply won't be re-installed because the in-flight
    /// marker has already been removed by the time we check on the build
    /// path. Safe to call even when no entry exists.
    public func remove<MachO: MachORepresentableWithCache>(for machO: MachO) {
        remove(key: machO.identifier)
    }

    /// Type-keyed variant matching ``storage()``.
    public func remove() {
        remove(key: currentIdentifer)
    }

    private func remove(key: AnyHashable) {
        _storageByIdentifier.withLockUnchecked { dict in
            if case .completed = dict[key] {
                dict.removeValue(forKey: key)
            }
        }
    }

    /// Drops every cached entry. Equivalent to the memory-pressure path but
    /// available to callers that want explicit control (e.g. tests, or a
    /// long-lived process flushing between unrelated batches).
    public func removeAll() {
        _storageByIdentifier.withLockUnchecked { dict in
            dict.removeAll(keepingCapacity: false)
        }
    }

    /// Shared core for both `storage(in:buildUsing:)` and `storage()`. Holds
    /// the cache lock only across the dictionary lookup / marker install and
    /// across the post-build dictionary update — the actual `build` call
    /// runs unsynchronized so that concurrent builds for distinct keys don't
    /// serialize.
    ///
    /// `package`-visible so the in-package test target can exercise the
    /// concurrency contract directly without manufacturing a fake
    /// `MachORepresentableWithCache` conformer.
    package func resolve(key: AnyHashable, build: () -> Storage?) -> Storage? {
        let outcome: Outcome = _storageByIdentifier.withLockUnchecked { dict in
            if let entry = dict[key] {
                switch entry {
                case .completed(let storage):
                    return .completed(storage)
                case .inFlight(let promise):
                    return .wait(promise)
                }
            }
            let promise = SharedCacheBuildPromise<Storage>()
            dict[key] = .inFlight(promise)
            return .build(promise)
        }

        switch outcome {
        case .completed(let storage):
            return storage
        case .wait(let promise):
            return promise.wait()
        case .build(let promise):
            let result = build()
            _storageByIdentifier.withLockUnchecked { dict in
                // Only publish back if our promise is still the in-flight
                // marker. `removeAll()` on memory pressure could have
                // cleared the dict mid-build, and a fresh caller may have
                // installed a different promise; in either case the dict is
                // not ours to write — but our promise still has waiters
                // attached, so we always call `fulfill(_:)` below.
                if case .inFlight(let installed) = dict[key], installed === promise {
                    if let storage = result {
                        dict[key] = .completed(storage)
                    } else {
                        // Mirror the original behaviour: a build that returns
                        // `nil` is not cached, so subsequent callers get a
                        // fresh attempt instead of being permanently stuck on
                        // the failure.
                        dict[key] = nil
                    }
                }
            }
            promise.fulfill(result)
            return result
        }
    }
}
