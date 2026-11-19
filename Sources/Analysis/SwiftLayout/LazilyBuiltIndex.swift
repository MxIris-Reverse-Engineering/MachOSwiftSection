import Foundation

/// One of an image's indexes, built the first time it is read.
///
/// The build runs outside the lock — it demangles, and a demangle may hop to
/// a large-stack thread, which must not happen while other readers wait on
/// the lock — and the first finished build is kept: readers racing on the
/// first read may each build the index, and all of them read the one that was
/// kept.
final class LazilyBuiltIndex<Index>: @unchecked Sendable {
    private let lock = NSLock()
    private var builtIndex: Index?

    func index(buildingWith build: () -> Index) -> Index {
        if let builtIndex = lock.withLock({ builtIndex }) {
            return builtIndex
        }
        let index = build()
        return lock.withLock {
            if let builtIndex {
                return builtIndex
            }
            builtIndex = index
            return index
        }
    }
}

extension LazilyBuiltIndex {
    /// Whether the index has been built.
    var isBuilt: Bool {
        lock.withLock { builtIndex != nil }
    }
}
