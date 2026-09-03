import Foundation
import FoundationToolbox
@_spi(Internals) import Demangling

/// Runs a library entry point on the demangler's large-stack task executor
/// (evolution proposal `large-stack-executor-and-cross-version-parallelism`).
///
/// `StackSafeExecutor` decides per demangle / print / remangle whether to hop
/// to an 8MB pool thread by probing the CALLING thread's remaining stack, not
/// its identity. Swift Concurrency's cooperative threads (and libdispatch's)
/// carry 512KB, so on them the probe never passes and every call pays a
/// thread round trip plus a semaphore wait — 8–21 µs each in release, 1.14–2.28×
/// the work itself. The synchronous indexing sweep amortizes that with one
/// `withLargeStack` batch (`SymbolIndexStore.buildStorageImpl`); an `async`
/// print loop cannot be enclosed in a synchronous batch. The upstream answer
/// (swift-demangling proposal 0014, shipped in 0.6.3) is a `TaskExecutor`
/// whose threads carry 16MB: a task running on it passes the probe at every
/// entry point, synchronous callees included, so the whole pipeline runs
/// inline with zero hops.
///
/// ``run(_:)`` is the one place this library adopts it. The async entry points
/// — indexer preparation, interface building and printing, the printer's
/// per-definition entries, diff / evolution preparation and rendering, and
/// the dump family — wrap their bodies in it, so a host gets the executor
/// without changing a line. Nesting is free: a task already on the executor
/// does not switch, so an entry point reached from another wrapped entry
/// point pays nothing.
///
/// Output is identical either way; only the thread the work runs on differs.
/// Where the runtime has no task executors (below macOS 15 / iOS 18 / tvOS 18
/// / watchOS 11 / visionOS 2, or off Darwin) the body runs unchanged on the
/// caller's executor — the pre-adoption behavior, hops included.
///
/// Two upstream contracts the wrapping honors: an unstructured `Task {}`
/// does not inherit the preference (SE-0417), so the library starts none
/// inside a wrapped entry point (child tasks and default actors do inherit);
/// and a job that blocks its thread waiting on another job of the same
/// quality-of-service class can exhaust that class's workers, exactly as it
/// would exhaust the cooperative pool — which is why cross-version
/// parallelism caps its window at the processor count.
public enum LargeStackTaskExecution {
    /// Process-wide switch. A host that manages its own executor sets it to
    /// `false`. The environment variable
    /// `MACHO_SWIFT_SECTION_LARGE_STACK_EXECUTOR=0` seeds it off for a process
    /// that cannot be recompiled — the rendering A/B and the timing runs
    /// compare the same binary with the executor on and off through it.
    @Mutex
    public static var isEnabled: Bool = ProcessInfo.processInfo.environment["MACHO_SWIFT_SECTION_LARGE_STACK_EXECUTOR"] != "0"

    /// Whether this process can run work on the executor at all: Darwin, on a
    /// runtime with SE-0417 task executors. Independent of ``isEnabled``.
    public static var isSupported: Bool {
        #if canImport(Darwin)
        if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
            return true
        }
        #endif
        return false
    }

    /// Runs `body` with the large-stack executor as the task executor
    /// preference when ``isEnabled`` and ``isSupported``; otherwise runs
    /// `body` unchanged on the caller's executor.
    ///
    /// The preference governs nonisolated async code, child tasks and default
    /// actors inside `body`. An actor with its own executor (the main actor)
    /// keeps its executor — the main thread's 8MB stack already passes the
    /// probe, so nothing is lost there.
    public static func run<Success: Sendable>(_ body: () async throws -> Success) async rethrows -> Success {
        #if canImport(Darwin)
        if isEnabled, #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
            return try await withTaskExecutorPreference(StackSafeExecutor.taskExecutor, operation: body)
        }
        #endif
        return try await body()
    }
}
