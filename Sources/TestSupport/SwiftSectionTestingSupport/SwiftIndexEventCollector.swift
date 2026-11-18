import Foundation
import SwiftDeclaration

/// Collects dispatched `SwiftIndexEvents` so a test can assert on the stream.
///
/// This replaced `StandardStreamCapture`, which asserted the same properties by
/// redirecting the process's `stderr` with `dup`/`dup2`. That approach could not
/// be made safe: `swift test` links every test target into one process, and
/// swift-testing's `.serialized` only serializes *within* a suite, so two suites
/// redirecting the same descriptors interleaved — one suite's saved copy kept
/// another's pipe write end open, the drain loop then never saw EOF, and the run
/// hung rather than failed. Attaching a handler needs no process-wide state, so
/// suites using this need no serialization from each other at all.
///
/// It is also a sharper assertion: the stream carries the failure's identity and
/// error, where stderr only carried "something was written".
public final class SwiftIndexEventCollector: SwiftIndexEvents.Handler, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SwiftIndexEvents.Payload] = []

    public init() {}

    public func handle(event: SwiftIndexEvents.Payload) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(event)
    }

    public var events: [SwiftIndexEvents.Payload] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// Names carried by `definitionPrintFailed` events, in dispatch order.
    public var printFailureNames: [String] {
        events.compactMap { event in
            guard case .definitionPrintFailed(let context, _) = event else { return nil }
            return context.name
        }
    }

    /// Names carried by `definitionPrintStarted` events, in dispatch order.
    public var printStartedNames: [String] {
        events.compactMap { event in
            guard case .definitionPrintStarted(let context) = event else { return nil }
            return context.name
        }
    }

    /// Degradation sources reported through `renderingDegraded`, in dispatch order.
    public var degradationSources: [SwiftIndexEvents.DegradationSource] {
        events.compactMap { event in
            guard case .renderingDegraded(let context, _) = event else { return nil }
            return context.source
        }
    }

    /// Subjects reported through `renderingDegraded`, skipping those with none.
    public var degradationSubjects: [String] {
        events.compactMap { event in
            guard case .renderingDegraded(let context, _) = event else { return nil }
            return context.subject
        }
    }

    /// Every reported loss, whichever event carried it — the partition
    /// `SwiftIndexEvents.Dispatcher` uses for its own zero-handler floor.
    public var failureDescriptions: [String] {
        events.compactMap(\.unhandledFailureDescription)
    }
}
