import Foundation
import Testing
import SwiftDeclaration

/// Pins the dispatcher's process-wide serialization of handler invocation
/// (evolution proposal `large-stack-executor-and-cross-version-parallelism`):
/// `SwiftIndexEvents.Handler` carries no `Sendable` requirement, and
/// cross-version preparation shares one host handler across N dispatchers on
/// N tasks, so without the lock a stateful handler is entered concurrently.
@Suite
struct EventDeliverySerializationTests {
    /// Counts concurrent entries into `handle`; a short spin inside makes an
    /// overlap near-certain when delivery is not serialized.
    private final class OverlapDetectingHandler: SwiftIndexEvents.Handler, @unchecked Sendable {
        private let lock = NSLock()
        private var inFlight = 0
        private(set) var maximumInFlight = 0
        private(set) var eventCount = 0

        func handle(event: SwiftIndexEvents.Payload) {
            lock.withLock {
                inFlight += 1
                maximumInFlight = max(maximumInFlight, inFlight)
                eventCount += 1
            }
            usleep(50)
            lock.withLock { inFlight -= 1 }
        }
    }

    @Test func aHandlerSharedByConcurrentDispatchersIsNeverEnteredConcurrently() async {
        let handler = OverlapDetectingHandler()
        let dispatcherCount = 4
        let eventsPerDispatcher = 200
        let dispatchers = (0 ..< dispatcherCount).map { _ in
            let dispatcher = SwiftIndexEvents.Dispatcher()
            dispatcher.addHandler(handler)
            return dispatcher
        }

        await withTaskGroup(of: Void.self) { group in
            for dispatcher in dispatchers {
                group.addTask {
                    for _ in 0 ..< eventsPerDispatcher {
                        dispatcher.dispatch(.moduleCollectionStarted)
                    }
                }
            }
        }

        #expect(handler.eventCount == dispatcherCount * eventsPerDispatcher)
        #expect(handler.maximumInFlight == 1, "handler was entered \(handler.maximumInFlight) times concurrently")
    }

    /// The lock is recursive: a handler that dispatches from inside `handle`
    /// (a host forwarding events into its own dispatcher) must not deadlock.
    private final class ReentrantHandler: SwiftIndexEvents.Handler, @unchecked Sendable {
        let inner = SwiftIndexEvents.Dispatcher()
        private let lock = NSLock()
        private(set) var outerCount = 0

        func handle(event: SwiftIndexEvents.Payload) {
            lock.withLock { outerCount += 1 }
            if case .moduleCollectionStarted = event {
                inner.dispatch(.moduleCollectionCompleted(result: .init(moduleCount: 0, modules: [])))
            }
        }
    }

    @Test(.timeLimit(.minutes(1))) func reentrantDispatchFromAHandlerDoesNotDeadlock() {
        let handler = ReentrantHandler()
        let innerHandler = OverlapDetectingHandler()
        handler.inner.addHandler(innerHandler)
        let outer = SwiftIndexEvents.Dispatcher()
        outer.addHandler(handler)

        outer.dispatch(.moduleCollectionStarted)

        #expect(handler.outerCount == 1)
        #expect(innerHandler.eventCount == 1)
    }
}
