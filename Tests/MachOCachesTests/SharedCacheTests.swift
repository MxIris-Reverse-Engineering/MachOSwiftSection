import Foundation
import Testing
import os
@_spi(Internals) import MachOCaches

@Suite("SharedCache.resolve")
struct SharedCacheResolveTests {
    /// Single-threaded sanity: a hit reuses the storage, a miss runs build,
    /// and a `nil` build is not cached.
    @Test func singleThreadedHitMissAndNilDontCache() {
        let cache = TestCache()

        let first = cache.resolve(key: AnyHashable("a")) { 1 }
        #expect(first == 1)

        // Second call hits the cache: the build closure must not run.
        let second = cache.resolve(key: AnyHashable("a")) {
            Issue.record("build was called for an already-cached key")
            return 99
        }
        #expect(second == 1)

        // A `nil` build is not cached, so the next call gets a fresh attempt.
        let nilFirst: Int? = cache.resolve(key: AnyHashable("b")) { nil }
        #expect(nilFirst == nil)

        let nilRetry = cache.resolve(key: AnyHashable("b")) { 7 }
        #expect(nilRetry == 7)
    }

    /// Concurrent calls for the **same** key must share one build — the
    /// promise-based marker is the whole point of this refactor over the
    /// previous "build under the global lock" implementation.
    @Test func concurrentCallsForSameKeyShareOneBuild() {
        let cache = TestCache()
        let buildCount = OSAllocatedUnfairLock(initialState: 0)
        let buildEnter = DispatchSemaphore(value: 0)
        let buildRelease = DispatchSemaphore(value: 0)
        let waiterCount = 32

        // First caller installs the in-flight marker and blocks inside
        // `build` until we release it. Every subsequent caller must attach
        // to that marker rather than invoking `build` again.
        let firstCallerDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let result = cache.resolve(key: AnyHashable("shared")) {
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
                let result = cache.resolve(key: AnyHashable("shared")) {
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
        let cache = TestCache()
        let keyCount = 8
        let perBuildSeconds: Double = 0.20

        let allDone = DispatchSemaphore(value: 0)
        let start = ContinuousClock.now
        for index in 0 ..< keyCount {
            DispatchQueue.global().async {
                _ = cache.resolve(key: AnyHashable(index)) {
                    Thread.sleep(forTimeInterval: perBuildSeconds)
                    return index
                }
                allDone.signal()
            }
        }
        for _ in 0 ..< keyCount { allDone.wait() }
        let elapsed = (ContinuousClock.now - start)
        let elapsedSeconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18

        // Allow generous slack for CI variance — the contract is "wall-clock
        // is closer to one build than to N builds", not a precise multiplier.
        // Serial would be ~keyCount * perBuildSeconds; we cap at half of
        // that, which is still >2× the parallel ideal.
        let serialCeiling = Double(keyCount) * perBuildSeconds
        let parallelBudget = serialCeiling * 0.5
        #expect(elapsedSeconds < parallelBudget,
                "elapsed=\(elapsedSeconds)s should be well below serial=\(serialCeiling)s")
    }

    /// Cache hits stay reentrant: a build for key A may itself call
    /// `resolve` for key B without deadlocking. (The fix releases the cache
    /// lock around the build call, so this is straightforward — but it's
    /// the whole reason the lock-during-build design was a problem to begin
    /// with, worth pinning.)
    @Test func buildClosureMayResolveOtherKey() {
        let cache = TestCache()
        let result = cache.resolve(key: AnyHashable("outer")) {
            cache.resolve(key: AnyHashable("inner")) { 5 }.map { $0 * 2 }
        }
        #expect(result == 10)
    }
}

/// Minimal SharedCache instantiation for tests. `SharedCache.init()` is
/// `package`-visible and constructs a usable cache without any MachO
/// scaffolding because every public entry point that requires
/// `MachORepresentableWithCache` ultimately delegates to `resolve(key:build:)`.
private final class TestCache: SharedCache<Int>, @unchecked Sendable {}

/// Mirror of ``SharedCacheResolveTests`` driven through Swift Concurrency
/// primitives (`TaskGroup`, `AsyncStream`) instead of GCD. `resolve` itself
/// is a sync function — calling it from a `Task` body still blocks the
/// cooperative thread pool while the promise's `wait()` is held, but the
/// cache contract (one build per key, parallelism across keys, reentrancy)
/// must hold regardless of how callers spawned the work.
@Suite("SharedCache.resolve under Swift Concurrency")
struct SharedCacheResolveSwiftConcurrencyTests {
    @Test func sameKeyDedupViaTaskGroup() async {
        let cache = TestCache()
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
                cache.resolve(key: AnyHashable("shared")) {
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
                    cache.resolve(key: AnyHashable("shared")) {
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

    @Test func differentKeysParallelViaTaskGroup() async {
        let cache = TestCache()
        let keyCount = 8
        let perBuildSeconds: Double = 0.20

        let start = ContinuousClock.now
        await withTaskGroup(of: Int?.self) { group in
            for index in 0 ..< keyCount {
                group.addTask {
                    cache.resolve(key: AnyHashable(index)) {
                        Thread.sleep(forTimeInterval: perBuildSeconds)
                        return index
                    }
                }
            }
            for await _ in group {}
        }
        let elapsed = ContinuousClock.now - start
        let elapsedSeconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18

        let serialCeiling = Double(keyCount) * perBuildSeconds
        let parallelBudget = serialCeiling * 0.5
        #expect(elapsedSeconds < parallelBudget,
                "elapsed=\(elapsedSeconds)s should be well below serial=\(serialCeiling)s — TaskGroup pool size and Thread.sleep blocking the cooperative pool both factor in, so this only verifies we are not fully serial")
    }

    /// async-let variant: build a small batch of distinct keys, then return
    /// the dictionary of results. Validates that the structured-concurrency
    /// `async let` form works the same as `TaskGroup` for distinct keys.
    @Test func differentKeysParallelViaAsyncLet() async {
        let cache = TestCache()
        let perBuildSeconds: Double = 0.10

        let start = ContinuousClock.now
        async let a = Task.detached {
            cache.resolve(key: AnyHashable("a")) {
                Thread.sleep(forTimeInterval: perBuildSeconds); return 1
            }
        }.value
        async let b = Task.detached {
            cache.resolve(key: AnyHashable("b")) {
                Thread.sleep(forTimeInterval: perBuildSeconds); return 2
            }
        }.value
        async let c = Task.detached {
            cache.resolve(key: AnyHashable("c")) {
                Thread.sleep(forTimeInterval: perBuildSeconds); return 3
            }
        }.value
        async let d = Task.detached {
            cache.resolve(key: AnyHashable("d")) {
                Thread.sleep(forTimeInterval: perBuildSeconds); return 4
            }
        }.value

        let results = await [a, b, c, d]
        let elapsed = ContinuousClock.now - start
        let elapsedSeconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18

        #expect(results == [1, 2, 3, 4])
        // Four 100ms builds run in parallel ⇒ wall-clock ≈ one build, well
        // below the serial ceiling of 4 × 100ms = 400ms.
        #expect(elapsedSeconds < 0.30)
    }

    /// Reentrancy from inside a Task body: a build for one key spawns a
    /// child Task that calls `resolve` for a different key, and the parent
    /// awaits the child's result. The fix's lock-free build path keeps this
    /// from deadlocking even though both calls share the same cache.
    @Test func reentrancyFromTask() async {
        let cache = TestCache()
        let outerResult = await Task.detached {
            cache.resolve(key: AnyHashable("outer")) {
                // Spawn a nested Task that resolves a different key. We can
                // only block-wait it because the outer build closure is
                // sync — `await` is not allowed here.
                let inner = Task.detached {
                    cache.resolve(key: AnyHashable("inner")) { 5 }
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
        let cache = TestCache()
        let buildCount = OSAllocatedUnfairLock(initialState: 0)
        let (buildEnteredStream, buildEnteredContinuation) =
            AsyncStream<Void>.makeStream()

        await withTaskGroup(of: Int?.self) { group in
            // Builder: blocks long enough that we can spawn-and-cancel a
            // herd of waiter tasks while it is still in flight.
            group.addTask {
                cache.resolve(key: AnyHashable("k")) {
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
                    cache.resolve(key: AnyHashable("k")) {
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
        let post = cache.resolve(key: AnyHashable("k")) {
            Issue.record("post-cancellation caller ran build, cache was corrupted")
            return -1
        }
        #expect(post == 99)
    }
}
