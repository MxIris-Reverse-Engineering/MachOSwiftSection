import Foundation
import MachOKit
import MachOKitExtensions

/// A `DependencyClosure` resolved once, on first use, and shared by every
/// consumer of one root — the property-wrapper catalog and the ObjC ancestor
/// resolver both ask for a file's dependency images lazily, and resolving
/// the closure twice would index every search-path cache twice (one pass over
/// a cache's images each; see `FileDependencyLocator`).
public final class SharedDependencyClosure<MachO: MachORepresentableWithCache>: @unchecked Sendable {
    private let resolve: @Sendable () -> DependencyClosure<MachO>
    private let lock = NSLock()
    private var resolved: DependencyClosure<MachO>?

    /// - Parameter resolve: Resolves the closure; called at most once, on the
    ///   first read of ``closure``, outside any lock the caller holds.
    public init(_ resolve: @escaping @Sendable () -> DependencyClosure<MachO>) {
        self.resolve = resolve
    }

    /// The closure, resolved on first read. Concurrent first readers
    /// serialize on the resolution; later reads are a lookup.
    public var closure: DependencyClosure<MachO> {
        lock.lock()
        defer { lock.unlock() }
        if let resolved { return resolved }
        let closure = resolve()
        resolved = closure
        return closure
    }

    /// Whether ``closure`` has been read yet.
    public var isResolved: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resolved != nil
    }
}
