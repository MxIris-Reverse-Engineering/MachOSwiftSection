import Foundation
import Testing
import os
@_spi(Internals) import MachOCaches

@Suite("SharedCache.resolve")
struct SharedCacheResolveTests {
    /// Single-threaded sanity: a hit reuses the storage, a miss runs build,
    /// and a `nil` build is not cached.
    @Test func singleThreadedHitMissAndNilDontCache() {
        let cache = makeTestCache()

        let first = cache.resolve(key: SharedCacheKey(opaque: "a")) { 1 }
        #expect(first == 1)

        // Second call hits the cache: the build closure must not run.
        let second = cache.resolve(key: SharedCacheKey(opaque: "a")) {
            Issue.record("build was called for an already-cached key")
            return 99
        }
        #expect(second == 1)

        // A `nil` build is not cached, so the next call gets a fresh attempt.
        let nilFirst: Int? = cache.resolve(key: SharedCacheKey(opaque: "b")) { nil }
        #expect(nilFirst == nil)

        let nilRetry = cache.resolve(key: SharedCacheKey(opaque: "b")) { 7 }
        #expect(nilRetry == 7)
    }

    /// Concurrent calls for the **same** key must share one build — the
    /// promise-based marker is the whole point of this refactor over the
    /// previous "build under the global lock" implementation.
    @Test func concurrentCallsForSameKeyShareOneBuild() {
        let cache = makeTestCache()
        let buildCount = OSAllocatedUnfairLock(initialState: 0)
        let buildEnter = DispatchSemaphore(value: 0)
        let buildRelease = DispatchSemaphore(value: 0)
        let waiterCount = 32

        // First caller installs the in-flight marker and blocks inside
        // `build` until we release it. Every subsequent caller must attach
        // to that marker rather than invoking `build` again.
        let firstCallerDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let result = cache.resolve(key: SharedCacheKey(opaque: "shared")) {
                buildCount.withLock { $0 += 1 }
                buildEnter.signal()
                buildRelease.wait()
                return 42
            }
            #expect(result == 42)
            firstCallerDone.signal()
        }

        buildEnter.wait()  // first caller is now blocked inside `build`

        // Fan out a herd of waiters; each must observe the same value and
        // none of them should have triggered another build.
        let herdDone = DispatchSemaphore(value: 0)
        let observed = OSAllocatedUnfairLock(initialState: [Int]())
        for _ in 0 ..< waiterCount {
            DispatchQueue.global().async {
                let result = cache.resolve(key: SharedCacheKey(opaque: "shared")) {
                    Issue.record("a waiter ran build instead of joining the in-flight promise")
                    return -1
                }
                observed.withLock { $0.append(result ?? -1) }
                herdDone.signal()
            }
        }

        // Give the herd a beat to all enter `resolve` and attach to the
        // promise. Without this delay the test could pass spuriously if the
        // first caller raced ahead of the waiters.
        Thread.sleep(forTimeInterval: 0.05)

        buildRelease.signal()                  // unblock the first caller
        firstCallerDone.wait()
        for _ in 0 ..< waiterCount { herdDone.wait() }

        #expect(buildCount.withLock { $0 } == 1, "build must run exactly once for the shared key")
        let values = observed.withLock { $0 }
        #expect(values.count == waiterCount)
        #expect(values.allSatisfy { $0 == 42 }, "every waiter must observe the builder's result")
    }

    /// Concurrent calls for **different** keys must build in parallel, not
    /// serialize behind one another. Verified by wall-clock: with the lock
    /// held over the build, N keys × T per build = N*T; with the promise
    /// fix, all N builds overlap, so wall-clock is ~T.
    @Test func concurrentCallsForDifferentKeysRunInParallel() {
        let cache = makeTestCache()
        // Two keys, not eight: every blocked build holds a libdispatch
        // worker, and under a saturated full-suite run eight workers were not
        // granted within the 30 s timeout (2026-09-28), which read as the
        // serialization failure this test exists to catch. Two builds prove
        // the overlap and cannot starve themselves.
        let keyCount = 2

        // Deterministic parallelism proof instead of a wall-clock heuristic
        // (which flaked under CPU saturation): every build blocks until all
        // `keyCount` builds have entered their closure. If `resolve`
        // serialized distinct keys — e.g. by holding the cache lock across
        // the build — the first build would wait forever for peers that can
        // never start, and the generous timeout below turns that into a
        // failure rather than a hang.
        let enteredBuild = DispatchSemaphore(value: 0)
        let proceedWithBuild = DispatchSemaphore(value: 0)
        let buildFinished = DispatchSemaphore(value: 0)
        let everyBuildEntered = OSAllocatedUnfairLock(initialState: true)

        // The coordinator waits for every build to enter its closure, then
        // releases them all at once. Its wait is *timed*, and it signals
        // `proceedWithBuild` even after timing out: an untimed wait would park
        // every build inside `resolve` for the rest of the process on failure,
        // stranding libdispatch threads and leaving those keys permanently
        // in-flight — a later test resolving them would then deadlock instead
        // of seeing this test's clean failure.
        DispatchQueue.global().async {
            for _ in 0 ..< keyCount {
                guard enteredBuild.wait(timeout: .now() + 30) == .success else {
                    everyBuildEntered.withLock { $0 = false }
                    break
                }
            }
            for _ in 0 ..< keyCount { proceedWithBuild.signal() }
        }

        for index in 0 ..< keyCount {
            DispatchQueue.global().async {
                _ = cache.resolve(key: SharedCacheKey(opaque: index)) {
                    enteredBuild.signal()
                    proceedWithBuild.wait()
                    return index
                }
                buildFinished.signal()
            }
        }

        var timedOut = false
        for _ in 0 ..< keyCount where !timedOut {
            timedOut = buildFinished.wait(timeout: .now() + 30) == .timedOut
        }
        #expect(!timedOut, "builds for distinct keys did not finish")
        #expect(everyBuildEntered.withLock { $0 }, "builds for distinct keys did not run concurrently: some build never entered its closure while the others were inside theirs")
    }

    /// Cache hits stay reentrant: a build for key A may itself call
    /// `resolve` for key B without deadlocking. (The fix releases the cache
    /// lock around the build call, so this is straightforward — but it's
    /// the whole reason the lock-during-build design was a problem to begin
    /// with, worth pinning.)
    @Test func buildClosureMayResolveOtherKey() {
        let cache = makeTestCache()
        let result = cache.resolve(key: SharedCacheKey(opaque: "outer")) {
            cache.resolve(key: SharedCacheKey(opaque: "inner")) { 5 }.map { $0 * 2 }
        }
        #expect(result == 10)
    }

    /// A build closure that resolves the **same** key on its own thread
    /// finds its own in-flight marker and would wait for a promise that only
    /// its own return can fulfill. That used to trap on the non-reentrant
    /// cache lock; after the promise rewrite it hung silently. The cache now
    /// traps on purpose, with a message naming the key, so the hang can never
    /// come back unnoticed. An exit test is the only way to pin a trap.
    @Test func reentrantBuildForTheSameKeyTrapsInsteadOfHanging() async {
        await #expect(processExitsWith: .failure) {
            let cache = makeTestCache()
            _ = cache.resolve(key: SharedCacheKey(opaque: "self")) {
                cache.resolve(key: SharedCacheKey(opaque: "self")) { 1 }
            }
        }
    }

    /// `register(_:for:)` installs a finished entry over whatever is there,
    /// an in-flight build included: the builder, once it returns, must not
    /// publish over the registered value — but it still hands its own result
    /// to the callers that joined it, since their promise is still its own.
    @Test func registeringOverAnInFlightBuildWinsAndTheBuilderStillAnswersItsWaiters() {
        let cache = makeTestCache()
        let key = SharedCacheKey(opaque: "k")
        let buildEnter = DispatchSemaphore(value: 0)
        let buildRelease = DispatchSemaphore(value: 0)
        let builderDone = DispatchSemaphore(value: 0)
        let builderResult = OSAllocatedUnfairLock<Int?>(initialState: nil)

        DispatchQueue.global().async {
            let result = cache.resolve(key: key) {
                buildEnter.signal()
                buildRelease.wait()
                return 1
            }
            builderResult.withLock { $0 = result }
            builderDone.signal()
        }
        buildEnter.wait()

        cache.register(2, forKey: key)
        #expect(cache.containsEntry(for: key), "a registered value is a finished entry at once, in-flight build or not")

        buildRelease.signal()
        builderDone.wait()

        #expect(builderResult.withLock { $0 } == 1, "the builder answers with what it built")
        let published = cache.resolve(key: key) {
            Issue.record("the registered entry must be found, not rebuilt")
            return -1
        }
        #expect(published == 2, "the builder must not publish over the registered entry")
    }
}

/// Every build blocks inside its closure until `expectedCount` builds have
/// entered theirs, then all of them return together. Two builds for
/// distinct keys can only both be inside their closures at once if the cache
/// does not hold its lock across the build — so the rendezvous completing is
/// the parallelism proof, with no wall-clock involved.
///
/// The wait is timed: on a scheduler that never gives the second build a
/// thread, an untimed wait would park the first build forever, hang the whole
/// test process and leave the key permanently in flight. On timeout every
/// waiter is released and ``everyBuildOverlapped`` reads `false`, which turns
/// the failure into an ordinary assertion.
private final class BuildRendezvous: @unchecked Sendable {
    private let condition = NSCondition()
    private let expectedCount: Int
    private let timeout: TimeInterval
    private var arrivedCount = 0
    private var isAbandoned = false

    init(expectedCount: Int, timeout: TimeInterval = 30) {
        self.expectedCount = expectedCount
        self.timeout = timeout
    }

    func arriveAndWait() {
        condition.lock()
        defer { condition.unlock() }
        arrivedCount += 1
        if arrivedCount >= expectedCount {
            condition.broadcast()
            return
        }
        let deadline = Date(timeIntervalSinceNow: timeout)
        while arrivedCount < expectedCount, !isAbandoned {
            if !condition.wait(until: deadline) {
                isAbandoned = true
                condition.broadcast()
            }
        }
    }

    /// `true` only when every expected build entered its closure while the
    /// earlier arrivals were still blocked inside theirs.
    var everyBuildOverlapped: Bool {
        condition.lock()
        defer { condition.unlock() }
        return !isAbandoned && arrivedCount == expectedCount
    }
}

/// The cache under test. `SharedCache.init(evictionGroup:registry:)` is
/// `package`-visible and constructs a usable cache without any Mach-O
/// scaffolding, because every entry point that takes a
/// `MachORepresentableWithCache` delegates to `resolve(key:build:)`.
private typealias TestCache = SharedCache<Int>

/// A cache registered with a registry of its own, so a test's caches never
/// take part in the process-wide registry's eviction sweeps.
private func makeTestCache() -> TestCache {
    SharedCache(evictionGroup: .symbolStore, registry: SharedCacheRegistry())
}

/// Mirror of ``SharedCacheResolveTests`` driven through Swift Concurrency
/// primitives (`TaskGroup`, `AsyncStream`) instead of GCD. `resolve` itself
/// is a sync function — calling it from a `Task` body still blocks the
/// cooperative thread pool while the promise's `wait()` is held, but the
/// cache contract (one build per key, parallelism across keys, reentrancy)
/// must hold regardless of how callers spawned the work.
@Suite("SharedCache.resolve under Swift Concurrency")
struct SharedCacheResolveSwiftConcurrencyTests {
    @Test func sameKeyDedupViaTaskGroup() async {
        let cache = makeTestCache()
        let buildCount = OSAllocatedUnfairLock(initialState: 0)
        let waiterCount = 16

        // One-shot signal: the first task yields when it has entered the
        // build closure (i.e. the in-flight marker is installed). Spawning
        // waiters before this point would race the marker install and could
        // false-pass the test.
        let (buildEnteredStream, buildEnteredContinuation) =
            AsyncStream<Void>.makeStream()

        await withTaskGroup(of: Int?.self) { group in
            group.addTask {
                cache.resolve(key: SharedCacheKey(opaque: "shared")) {
                    buildCount.withLock { $0 += 1 }
                    buildEnteredContinuation.yield()
                    buildEnteredContinuation.finish()
                    // Stay inside the build long enough for the spawned
                    // waiter tasks to attach to the in-flight promise.
                    // Sync sleep is required: the build closure is sync,
                    // and `await Task.sleep` would compile-error here.
                    Thread.sleep(forTimeInterval: 0.2)
                    return 42
                }
            }

            // Wait until the builder has entered `resolve` (deterministic).
            var iterator = buildEnteredStream.makeAsyncIterator()
            _ = await iterator.next()

            for _ in 0 ..< waiterCount {
                group.addTask {
                    cache.resolve(key: SharedCacheKey(opaque: "shared")) {
                        Issue.record("waiter ran build instead of joining the in-flight promise")
                        return -1
                    }
                }
            }

            var values: [Int?] = []
            for await result in group {
                values.append(result)
            }

            #expect(buildCount.withLock { $0 } == 1,
                    "build must run exactly once for the shared key")
            #expect(values.count == waiterCount + 1)
            #expect(values.allSatisfy { $0 == 42 },
                    "every Task must observe the builder's result")
        }
    }

    /// Builds for distinct keys spawned as TaskGroup children must overlap.
    /// Proven by rendezvous rather than by wall-clock: each build blocks
    /// inside its closure until the other has entered too, which can only
    /// happen if the cache releases its lock around the build. The earlier
    /// form timed 8 sleeping builds against half the serial ceiling, and
    /// failed whenever a loaded full-suite run starved the cooperative pool.
    ///
    /// Two builds, not eight: every build blocks a cooperative-pool thread
    /// while it waits, and the pool is only as wide as the core count and is
    /// shared with every other test in the process. Two is the smallest
    /// count that proves overlap and the largest that cannot starve itself.
    @Test func differentKeysParallelViaTaskGroup() async {
        let cache = makeTestCache()
        let keyCount = 2
        let rendezvous = BuildRendezvous(expectedCount: keyCount)

        var results: [Int?] = []
        await withTaskGroup(of: Int?.self) { group in
            for index in 0 ..< keyCount {
                group.addTask {
                    cache.resolve(key: SharedCacheKey(opaque: index)) {
                        rendezvous.arriveAndWait()
                        return index
                    }
                }
            }
            for await result in group {
                results.append(result)
            }
        }

        #expect(results.compactMap { $0 }.sorted() == Array(0 ..< keyCount))
        #expect(rendezvous.everyBuildOverlapped,
                "builds for distinct keys did not overlap: the second build never entered its closure while the first was still inside its own")
    }

    /// async-let variant of the rendezvous above: the structured-concurrency
    /// `async let` form must give distinct keys the same overlap that the
    /// TaskGroup form does.
    @Test func differentKeysParallelViaAsyncLet() async {
        let cache = makeTestCache()
        let rendezvous = BuildRendezvous(expectedCount: 2)

        async let first = Task.detached {
            cache.resolve(key: SharedCacheKey(opaque: "a")) {
                rendezvous.arriveAndWait()
                return 1
            }
        }.value
        async let second = Task.detached {
            cache.resolve(key: SharedCacheKey(opaque: "b")) {
                rendezvous.arriveAndWait()
                return 2
            }
        }.value

        let results = await [first, second]

        #expect(results == [1, 2])
        #expect(rendezvous.everyBuildOverlapped,
                "builds for distinct keys did not overlap: the second build never entered its closure while the first was still inside its own")
    }

    /// Reentrancy from inside a Task body: a build for one key spawns a
    /// child Task that calls `resolve` for a different key, and the parent
    /// awaits the child's result. The fix's lock-free build path keeps this
    /// from deadlocking even though both calls share the same cache.
    @Test func reentrancyFromTask() async {
        let cache = makeTestCache()
        let outerResult = await Task.detached {
            cache.resolve(key: SharedCacheKey(opaque: "outer")) {
                // Spawn a nested Task that resolves a different key. We can
                // only block-wait it because the outer build closure is
                // sync — `await` is not allowed here.
                let inner = Task.detached {
                    cache.resolve(key: SharedCacheKey(opaque: "inner")) { 5 }
                }
                // `Task.value` is async, so we hop back through a Dispatch
                // semaphore — proves reentrancy works regardless of how the
                // caller chooses to bridge.
                let semaphore = DispatchSemaphore(value: 0)
                let result = OSAllocatedUnfairLock<Int?>(initialState: nil)
                Task {
                    let value = await inner.value
                    result.withLock { $0 = value }
                    semaphore.signal()
                }
                semaphore.wait()
                let value = result.withLock { $0 }
                return value.map { $0 * 2 }
            }
        }.value
        #expect(outerResult == 10)
    }

    /// Cancelling Tasks that are blocked inside `resolve.wait()` must not
    /// corrupt cache state: the in-flight build still completes, the cache
    /// still publishes the result, and a fresh post-cancellation caller
    /// observes the cached value rather than re-running the build.
    @Test func cancellingWaitersLeavesCacheIntact() async {
        let cache = makeTestCache()
        let buildCount = OSAllocatedUnfairLock(initialState: 0)
        let (buildEnteredStream, buildEnteredContinuation) =
            AsyncStream<Void>.makeStream()

        await withTaskGroup(of: Int?.self) { group in
            // Builder: blocks long enough that we can spawn-and-cancel a
            // herd of waiter tasks while it is still in flight.
            group.addTask {
                cache.resolve(key: SharedCacheKey(opaque: "k")) {
                    buildCount.withLock { $0 += 1 }
                    buildEnteredContinuation.yield()
                    buildEnteredContinuation.finish()
                    Thread.sleep(forTimeInterval: 0.15)
                    return 99
                }
            }

            var iterator = buildEnteredStream.makeAsyncIterator()
            _ = await iterator.next()

            // Spawn waiters and immediately cancel them. `resolve` doesn't
            // observe Task cancellation (it's a sync function), so they
            // still complete with the builder's result; we just verify that
            // the cache is not poisoned by the cancellation.
            for _ in 0 ..< 8 {
                let task = Task.detached {
                    cache.resolve(key: SharedCacheKey(opaque: "k")) {
                        Issue.record("waiter ran build")
                        return -1
                    }
                }
                task.cancel()
                group.addTask { await task.value }
            }

            for await _ in group {}
        }

        #expect(buildCount.withLock { $0 } == 1,
                "build must run exactly once even when waiter tasks are cancelled")

        // After the builder published, the cache should hold the result —
        // a fresh caller must not trigger another build.
        let post = cache.resolve(key: SharedCacheKey(opaque: "k")) {
            Issue.record("post-cancellation caller ran build, cache was corrupted")
            return -1
        }
        #expect(post == 99)
    }
}
