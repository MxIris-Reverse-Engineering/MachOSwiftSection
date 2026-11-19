import Foundation
import Testing
import SwiftDeclaration
@testable import SwiftIndexing

/// Pins `ConsoleEventHandler`'s line format, in particular the input label
/// (evolution proposal `large-stack-executor-and-cross-version-parallelism`):
/// `diff` / `evolution` index their inputs concurrently, so every stderr line
/// carries `[label]` after the timestamp when a label is set, and nothing
/// extra when it is not.
@Suite
struct ConsoleEventHandlerLineTests {
    private let completedExtraction = SwiftIndexEvents.Payload.extractionCompleted(
        result: SwiftIndexEvents.ExtractionResult(section: .swiftTypes, count: 42)
    )

    @Test func labeledLinesCarryTheLabelAfterTheTimestamp() {
        let handler = ConsoleEventHandler(label: "26.0")
        #expect(handler.line(for: completedExtraction, timestamp: "12:00:00") == "[12:00:00] [26.0] [INFO] Extracted 42 Swift types")
    }

    @Test func unlabeledLinesAreUnchanged() {
        let handler = ConsoleEventHandler()
        #expect(handler.label == nil)
        #expect(handler.line(for: completedExtraction, timestamp: "12:00:00") == "[12:00:00] [INFO] Extracted 42 Swift types")
    }

    @Test func unreportedEventsProduceNoLine() {
        let handler = ConsoleEventHandler(label: "old")
        #expect(handler.line(for: .moduleCollectionStarted, timestamp: "12:00:00") == nil)
        #expect(handler.line(for: .phaseTransition(phase: .indexing, state: .started), timestamp: "12:00:00") == nil)
    }

    @Test func failuresKeepTheLabelToo() {
        struct Failure: Error, CustomStringConvertible { var description: String { "boom" } }
        let handler = ConsoleEventHandler(label: "new")
        let line = handler.line(for: .phaseTransition(phase: .indexing, state: .failed(Failure())), timestamp: "12:00:00")
        #expect(line == "[12:00:00] [new] [ERROR] Indexing failed: boom")
    }

    /// Most events — one per type, conformance and printed declaration —
    /// print nothing. Stamping each of them with the local time built a date
    /// formatter per event: a quarter of `swift-section interface` over SwiftUI.
    @Test func unreportedEventsAskForNoTimestamp() {
        let timestampRequests = TimestampRequestCounter()
        let handler = ConsoleEventHandler(label: nil) {
            timestampRequests.increment()
            return "12:00:00"
        }

        handler.handle(event: .moduleCollectionStarted)
        handler.handle(event: .phaseTransition(phase: .indexing, state: .started))

        #expect(timestampRequests.count == 0)
    }
}

private final class TimestampRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var requestCount = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        requestCount += 1
    }
}
