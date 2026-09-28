import Foundation

/// Sync rendezvous used by ``SharedCache/storage(in:buildUsing:)`` to share
/// one in-flight build between concurrent callers for the same identifier.
///
/// The first caller installs an instance of this promise as the cache's
/// in-flight marker for the key, releases the cache lock, and runs the build
/// closure unsynchronized. Concurrent callers for the same key find the
/// in-flight marker, release the cache lock, and block in ``wait()`` on
/// `NSCondition`. The builder calls ``fulfill(_:)`` once the work is done,
/// `broadcast()` wakes every waiter at once, and `wait()` returns the same
/// value to all of them.
///
/// `final class` because the same instance must be referenced from the cache
/// dictionary and from every waiter; `NSCondition` also requires a stable
/// memory address. `@unchecked Sendable` because the synchronization is
/// provided by `NSCondition`, not by Swift's data-race detector.
@_spi(Internals)
public final class SharedCacheBuildPromise<Value>: @unchecked Sendable {
    private let condition = NSCondition()
    /// The thread that installed this promise and runs the build it stands
    /// for. `SharedCache.resolve` creates the promise on the very thread that
    /// goes on to call the build closure, so the thread is captured here and
    /// never assigned again. A build that hops to another thread (the symbol
    /// index sweep moves onto a large-stack worker) is not covered by this:
    /// only the builder's own thread can be told apart from a legitimate
    /// waiter, which is the case ``isBuilderCurrentThread`` exists for.
    private let builderThread: pthread_t = pthread_self()
    /// Outer optional encodes "fulfilled yet?"; inner optional matches
    /// `(MachO) -> Storage?` — a build that returned `nil` is a valid
    /// terminal state, distinct from "still pending".
    private var result: Value??

    public init() {}

    /// `true` when the calling thread is the one running this promise's
    /// build. A `wait()` from that thread can never return: the promise is
    /// fulfilled only after the build closure returns, and the build closure
    /// is what is waiting. `SharedCache.resolve` checks this before waiting
    /// and traps with a message instead of hanging silently.
    public var isBuilderCurrentThread: Bool {
        pthread_equal(builderThread, pthread_self()) != 0
    }

    /// Blocks until ``fulfill(_:)`` is called and returns whatever the builder
    /// produced. Safe to call from any thread.
    public func wait() -> Value? {
        condition.lock()
        defer { condition.unlock() }
        while result == nil {
            condition.wait()
        }
        // `result` is `.some(.some(v))` or `.some(.none)`; flatten the outer
        // optional we used as the "fulfilled" tag back to the inner Storage?.
        return result.flatMap { $0 }
    }

    /// Records the result and wakes every waiter. Idempotent — a second call
    /// is silently ignored, which matters when memory pressure clears the
    /// cache mid-build and a fresh builder installs a new promise: the old
    /// builder's `fulfill` call still has to land for its already-blocked
    /// waiters, but mustn't disturb the new promise.
    public func fulfill(_ value: Value?) {
        condition.lock()
        defer { condition.unlock() }
        if result != nil { return }
        result = .some(value)
        condition.broadcast()
    }
}
