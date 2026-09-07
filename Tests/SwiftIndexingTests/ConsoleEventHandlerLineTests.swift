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
}
