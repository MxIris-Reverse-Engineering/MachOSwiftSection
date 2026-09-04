import Foundation
import Testing
import MachOFoundation

/// Pins `concurrentMap(maximumConcurrency:_:)` (evolution proposal
/// `large-stack-executor-and-cross-version-parallelism`), the windowed
/// scheduler behind cross-version preparation: source-ordered results, a
/// window that is never exceeded, a window of 1 that is strictly serial,
/// genuine concurrency inside the window, and first-failure semantics that
/// never start the elements still pending.
///
/// No wall-clock assertions: the ordering and window facts are recorded
/// through locks and rendezvous, so a loaded machine cannot fail them.
@Suite
struct BoundedConcurrentMapTests {
    /// Records start/end events and the in-flight high-water mark.
    private final class Ledger: @unchecked Sendable {
        private let lock = NSLock()
        private var inFlight = 0
        private(set) var maximumInFlight = 0
        private(set) var events: [String] = []

        func start(_ element: Int) {
            lock.withLock {
                inFlight += 1
                maximumInFlight = max(maximumInFlight, inFlight)
                events.append("start \(element)")
            }
        }

        func end(_ element: Int) {
            lock.withLock {
                inFlight -= 1
                events.append("end \(element)")
            }
        }
    }

    /// A rendezvous for a fixed number of participants: `arrive()` suspends
    /// until every participant has arrived, so it completes only if that many
    /// transforms are in flight at the same time.
    private actor Barrier {
        private let participantCount: Int
        private var arrivedCount = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(participantCount: Int) {
            self.participantCount = participantCount
        }

        func arrive() async {
            arrivedCount += 1
            if arrivedCount >= participantCount {
                for waiter in waiters { waiter.resume() }
                waiters.removeAll()
                return
            }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    /// A one-shot gate: `wait()` suspends until `open()` — a rendezvous that
    /// completes only if the waiter and the opener run concurrently.
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
    }

    @Test func resultsKeepSourceOrderWhateverTheCompletionOrder() async throws {
        let elements = Array(0 ..< 12)
        let results = try await elements.concurrentMap(maximumConcurrency: 4) { element in
            // Later elements finish first when they can.
            try await Task.sleep(nanoseconds: UInt64(12 - element) * 1_000_000)
            return element * 10
        }
        #expect(results == elements.map { $0 * 10 })
    }

    @Test func theWindowIsNeverExceeded() async throws {
        let ledger = Ledger()
        _ = try await Array(0 ..< 10).concurrentMap(maximumConcurrency: 3) { element in
            ledger.start(element)
            try await Task.sleep(nanoseconds: 5_000_000)
            ledger.end(element)
        }
        #expect(ledger.maximumInFlight <= 3)
        #expect(ledger.events.count == 20)
    }

    @Test func aWindowOfOneIsStrictlySerialInSourceOrder() async throws {
        let ledger = Ledger()
        _ = try await Array(0 ..< 5).concurrentMap(maximumConcurrency: 1) { element in
            ledger.start(element)
            await Task.yield()
            ledger.end(element)
        }
        let expected = (0 ..< 5).flatMap { ["start \($0)", "end \($0)"] }
        #expect(ledger.events == expected)
        #expect(ledger.maximumInFlight == 1)
    }

    @Test func valuesBelowOneCountAsOne() async throws {
        let ledger = Ledger()
        _ = try await Array(0 ..< 3).concurrentMap(maximumConcurrency: 0) { element in
            ledger.start(element)
            await Task.yield()
            ledger.end(element)
        }
        #expect(ledger.maximumInFlight == 1)
    }

    /// Two elements in a window of two must run at the same time: the first
    /// waits on a gate only the second opens. A serial scheduler would never
    /// reach the opener — hence the time limit, which is the failure mode.
    @Test(.timeLimit(.minutes(1))) func elementsInsideTheWindowRunConcurrently() async throws {
        let gate = Gate()
        let results = try await [0, 1].concurrentMap(maximumConcurrency: 2) { element in
            if element == 0 {
                await gate.wait()
            } else {
                await gate.open()
            }
            return element
        }
        #expect(results == [0, 1])
    }

    /// The window admits exactly its width, not fewer: three elements in a
    /// window of three must all be in flight at once (a three-way barrier that
    /// only releases when all three have arrived). A window that admitted two
    /// would leave the third pending forever — hence the time limit.
    @Test(.timeLimit(.minutes(1))) func theWindowAdmitsItsFullWidth() async throws {
        let barrier = Barrier(participantCount: 3)
        let results = try await [0, 1, 2].concurrentMap(maximumConcurrency: 3) { element in
            await barrier.arrive()
            return element
        }
        #expect(results == [0, 1, 2])
    }

    /// Cancelling the calling task stops the submission of pending elements
    /// and fails the call with `CancellationError` — never a partial array.
    /// Element 0 holds the (width-1) window open until the test has cancelled
    /// the task; element 1 must then never start. The first version used
    /// `addTask`, which a cancelled group still accepts, so every remaining
    /// version of a cancelled multi-version preparation indexed to the end.
    @Test(.timeLimit(.minutes(1))) func cancellationStopsSubmittingPendingElements() async {
        let ledger = Ledger()
        let elementZeroStarted = Gate()
        let elementZeroMayFinish = Gate()

        let task = Task {
            try await Array(0 ..< 4).concurrentMap(maximumConcurrency: 1) { element in
                ledger.start(element)
                if element == 0 {
                    await elementZeroStarted.open()
                    await elementZeroMayFinish.wait()
                }
                ledger.end(element)
            }
        }

        await elementZeroStarted.wait()
        task.cancel()
        await elementZeroMayFinish.open()

        let outcome = await task.result
        #expect(throws: CancellationError.self) { try outcome.get() }
        #expect(ledger.events == ["start 0", "end 0"])
    }

    @Test func theFirstFailureIsRethrownAndPendingElementsNeverStart() async {
        struct Failure: Error, Equatable {
            let element: Int
        }
        let ledger = Ledger()
        await #expect(throws: Failure(element: 1)) {
            _ = try await Array(0 ..< 5).concurrentMap(maximumConcurrency: 1) { element in
                ledger.start(element)
                defer { ledger.end(element) }
                if element == 1 { throw Failure(element: element) }
            }
        }
        // Serial window: element 0 completed, element 1 threw, 2…4 never started.
        #expect(ledger.events == ["start 0", "end 0", "start 1", "end 1"])
    }

    @Test func emptyInputYieldsEmptyOutput() async throws {
        let results = try await [Int]().concurrentMap(maximumConcurrency: 4) { $0 }
        #expect(results.isEmpty)
    }
}
