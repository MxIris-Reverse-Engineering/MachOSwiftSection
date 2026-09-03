import Foundation
import Testing
@_spi(Internals) import Demangling
@testable import MachOSymbols

/// Pins `LargeStackTaskExecution.run` (evolution proposal
/// `large-stack-executor-and-cross-version-parallelism`): on a runtime with
/// task executors the body runs on one of the demangler's 16MB executor
/// threads and every demangler entry inside it runs inline (no hop to the
/// 8MB pool); nested runs do not switch threads; disabled or unsupported, the
/// body runs where the caller was. The upstream executor's own behavior
/// (thread size, QoS class, fallbacks) is pinned by swift-demangling's
/// `LargeStackTaskExecutorTests`; these tests cover the adoption seam only.
///
/// Serialized: `disabledRunsTheBodyOnTheCallersExecutor` flips the
/// process-wide switch, and a parallel sibling asserting on the executor
/// thread would read it mid-flip.
@Suite(.serialized)
struct LargeStackTaskExecutionTests {
    /// The upstream executor names its workers after itself
    /// (`swift-demangling.task-executor.<qos>`); the prefix is the observable
    /// identity of "an executor thread" from this side of the module boundary.
    private static let executorThreadNamePrefix = "swift-demangling.task-executor."

    private static func currentThreadName() -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        pthread_getname_np(pthread_self(), &buffer, buffer.count)
        return String(cString: buffer)
    }

    private static func currentThread() -> mach_port_t {
        pthread_mach_thread_np(pthread_self())
    }

    @Test func bodyRunsOnAnExecutorThreadWhenSupported() async {
        guard LargeStackTaskExecution.isSupported else { return }
        let (stackSize, threadName) = await LargeStackTaskExecution.run {
            (pthread_get_stacksize_np(pthread_self()), Self.currentThreadName())
        }
        #expect(stackSize >= 16 * 1024 * 1024, "stack was \(stackSize) bytes")
        #expect(threadName.hasPrefix(Self.executorThreadNamePrefix), "ran on \(threadName)")
    }

    /// The property the adoption exists for: inside the body, the demangler's
    /// stack probe passes, so its blocking and suspending entries stay on the
    /// task's thread instead of hopping to a pool worker.
    @Test func demanglerEntriesInsideTheBodyDoNotHop() async {
        guard LargeStackTaskExecution.isSupported else { return }
        let observation = await LargeStackTaskExecution.run {
            let taskThread = Self.currentThread()
            let blockingCallThread: mach_port_t = StackSafeExecutor.execute { Self.currentThread() }
            let suspendingCallThread: mach_port_t = await StackSafeExecutor.executeAsync { Self.currentThread() }
            return (taskThread, blockingCallThread, suspendingCallThread)
        }
        #expect(observation.1 == observation.0, "execute hopped off the executor thread")
        #expect(observation.2 == observation.0, "executeAsync hopped off the executor thread")
    }

    /// Every wrapped entry point reached from another wrapped entry point
    /// (`printRoot` → `printTypeDefinition`, a parent's nested-children loop)
    /// nests a run inside a run; the inner one must not move the task.
    @Test func nestedRunsStayOnTheSameThread() async {
        guard LargeStackTaskExecution.isSupported else { return }
        let (outerThread, innerThread) = await LargeStackTaskExecution.run {
            let outer = Self.currentThread()
            let inner = await LargeStackTaskExecution.run { Self.currentThread() }
            return (outer, inner)
        }
        #expect(innerThread == outerThread)
    }

    /// Child tasks inherit the preference (SE-0417) — the cross-version
    /// parallel preparation relies on this.
    @Test func childTasksInheritTheExecutor() async {
        guard LargeStackTaskExecution.isSupported else { return }
        let childThreadNames = await LargeStackTaskExecution.run {
            await withTaskGroup(of: String.self) { group in
                for _ in 0 ..< 3 {
                    group.addTask { Self.currentThreadName() }
                }
                return await group.reduce(into: [String]()) { $0.append($1) }
            }
        }
        #expect(childThreadNames.count == 3)
        for threadName in childThreadNames {
            #expect(threadName.hasPrefix(Self.executorThreadNamePrefix), "child ran on \(threadName)")
        }
    }

    @Test func disabledRunsTheBodyOnTheCallersExecutor() async {
        let wasEnabled = LargeStackTaskExecution.isEnabled
        LargeStackTaskExecution.isEnabled = false
        defer { LargeStackTaskExecution.isEnabled = wasEnabled }

        let callerThread = Self.currentThread()
        let (bodyThread, threadName) = await LargeStackTaskExecution.run { (Self.currentThread(), Self.currentThreadName()) }
        // No switch at all: a non-suspending body on the caller's executor
        // completes on the very thread that entered it.
        #expect(bodyThread == callerThread)
        #expect(!threadName.hasPrefix(Self.executorThreadNamePrefix), "ran on \(threadName)")
    }

    @Test func valuesAndErrorsPassThrough() async throws {
        struct Failure: Error, Equatable {}

        let value = await LargeStackTaskExecution.run { 42 }
        #expect(value == 42)

        await #expect(throws: Failure.self) {
            try await LargeStackTaskExecution.run { throw Failure() }
        }
    }
}
