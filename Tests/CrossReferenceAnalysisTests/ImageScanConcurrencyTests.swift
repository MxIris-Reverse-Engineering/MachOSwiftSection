import Foundation
import Testing

/// Pins `ImageScanConcurrency` (evolution proposal
/// `cross-reference-test-scan-load`): every index runs once, and no more
/// bodies run at once than the budget — within one call, and across calls
/// made at the same time, which is what Swift Testing's parallel suites do.
@Suite
struct ImageScanConcurrencyTests {
    @Test func everyIterationRunsExactlyOnce() {
        let runs = RunCounter(iterationCount: 1000)
        ImageScanConcurrency.concurrentPerform(iterations: 1000) { index in
            runs.record(index)
        }
        #expect(runs.indicesNotRunExactlyOnce.isEmpty)
    }

    @Test func noMoreThanTheBudgetRunAtOnce() {
        let tracker = InFlightTracker()
        ImageScanConcurrency.concurrentPerform(iterations: 300) { _ in
            tracker.run { Thread.sleep(forTimeInterval: 0.002) }
        }
        #expect(tracker.completedCount == 300)
        #expect(tracker.peak <= ImageScanConcurrency.maximumConcurrentScans)
    }

    /// The other call runs on a thread of its own, never on a pool thread
    /// this test would block waiting for.
    @Test func twoCallsAtOnceShareTheBudget() {
        let tracker = InFlightTracker()
        let otherCallFinished = DispatchSemaphore(value: 0)
        Thread {
            ImageScanConcurrency.concurrentPerform(iterations: 300) { _ in
                tracker.run { Thread.sleep(forTimeInterval: 0.002) }
            }
            otherCallFinished.signal()
        }.start()
        ImageScanConcurrency.concurrentPerform(iterations: 300) { _ in
            tracker.run { Thread.sleep(forTimeInterval: 0.002) }
        }
        otherCallFinished.wait()
        #expect(tracker.completedCount == 600)
        #expect(tracker.peak <= ImageScanConcurrency.maximumConcurrentScans)
    }

    @Test func zeroIterationsReturnWithoutRunning() {
        let tracker = InFlightTracker()
        ImageScanConcurrency.concurrentPerform(iterations: 0) { _ in
            tracker.run {}
        }
        #expect(tracker.completedCount == 0)
    }
}

/// How many times each index ran.
private final class RunCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [Int]

    init(iterationCount: Int) {
        counts = Array(repeating: 0, count: iterationCount)
    }

    func record(_ index: Int) {
        lock.lock()
        defer { lock.unlock() }
        counts[index] += 1
    }

    var indicesNotRunExactlyOnce: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return counts.indices.filter { counts[$0] != 1 }
    }
}

/// The most bodies seen running at once, and how many finished.
private final class InFlightTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var running = 0
    private var highestRunning = 0
    private var completed = 0

    func run(_ body: () -> Void) {
        lock.lock()
        running += 1
        highestRunning = max(highestRunning, running)
        lock.unlock()
        body()
        lock.lock()
        running -= 1
        completed += 1
        lock.unlock()
    }

    var peak: Int {
        lock.lock()
        defer { lock.unlock() }
        return highestRunning
    }

    var completedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }
}
