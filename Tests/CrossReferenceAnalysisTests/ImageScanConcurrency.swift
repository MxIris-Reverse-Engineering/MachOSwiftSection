import Foundation

/// How many images this target's parallel scans may read at once: half of the
/// cores, at least two.
///
/// A Debug scan of the whole shared cache keeps every core it is given busy
/// for minutes, and Swift Testing runs the suites holding these scans in
/// parallel. The budget is therefore one for the whole process, not one per
/// call: four suites with a width each would add up to every core again
/// (evolution proposal `cross-reference-test-scan-load`).
/// `ParallelScanSourceTests` keeps every parallel scan of the target on it.
enum ImageScanConcurrency {
    static let maximumConcurrentScans = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)

    private static let permits = DispatchSemaphore(value: maximumConcurrentScans)

    /// Runs `body` once for every index in `0 ..< iterations`, as
    /// `DispatchQueue.concurrentPerform(iterations:execute:)` does, with at
    /// most `maximumConcurrentScans` bodies running at once across the
    /// process.
    ///
    /// Each call starts no more workers than the budget, so the threads
    /// waiting for a permit stay bounded; each worker takes the next index and
    /// holds a permit only while its body runs. A permit is never held across
    /// a wait for other work, so the callers — the calling thread of
    /// `concurrentPerform` may be a cooperative thread — always get one in the
    /// end.
    ///
    /// `body` must not call this function again: a nested call waits for a
    /// permit while its caller holds one, and with every permit held that way
    /// none is ever released.
    static func concurrentPerform(iterations: Int, execute body: (Int) -> Void) {
        guard iterations > 0 else { return }
        let cursor = IterationCursor(iterationCount: iterations)
        DispatchQueue.concurrentPerform(iterations: min(maximumConcurrentScans, iterations)) { _ in
            while let index = cursor.next() {
                permits.wait()
                defer { permits.signal() }
                body(index)
            }
        }
    }
}

/// Hands out each index of `0 ..< iterationCount` once, to whichever worker
/// asks first.
private final class IterationCursor: @unchecked Sendable {
    private let lock = NSLock()
    private let iterationCount: Int
    private var nextIndex = 0

    init(iterationCount: Int) {
        self.iterationCount = iterationCount
    }

    func next() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard nextIndex < iterationCount else { return nil }
        defer { nextIndex += 1 }
        return nextIndex
    }
}
