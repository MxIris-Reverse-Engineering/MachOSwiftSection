extension Collection where Element: Sendable {
    /// Transforms every element with at most `maximumConcurrency` transforms
    /// in flight, returning the results in source order.
    ///
    /// Submission is windowed: the first `maximumConcurrency` elements start
    /// at once and each completion admits the next, so a bounded number of
    /// transforms ever runs concurrently — the shape cross-version preparation
    /// needs (evolution proposal
    /// `large-stack-executor-and-cross-version-parallelism`), where each
    /// in-flight transform holds an indexed image's memory and a thread. A
    /// `maximumConcurrency` of 1 runs the elements strictly one after the
    /// other, in order; values below 1 count as 1.
    ///
    /// Two things stop the submission of elements not yet started, and in
    /// both the pending elements never start: the first failure, which is
    /// rethrown; and cancellation of the calling task, after which the call
    /// throws `CancellationError` — never a partial array. Transforms already
    /// in flight run to completion first (a task group waits for its
    /// children, and the transforms this library passes do not observe
    /// cancellation), and their results are discarded. A cancellation that
    /// arrives after the last element was submitted changes nothing: the
    /// work is done, so the results are returned.
    ///
    /// Child tasks inherit the caller's task executor preference, so under
    /// `LargeStackTaskExecution.run` every transform runs on the large-stack
    /// executor.
    public func concurrentMap<Result: Sendable>(
        maximumConcurrency: Int,
        _ transform: @escaping @Sendable (Element) async throws -> Result
    ) async throws -> [Result] {
        let window = Swift.max(1, maximumConcurrency)
        return try await withThrowingTaskGroup(of: (index: Int, result: Result).self) { group in
            var results = [Result?](repeating: nil, count: count)
            var pending = enumerated().makeIterator()

            // `addTaskUnlessCancelled`, not `addTask`: a cancelled group still
            // accepts children through `addTask`, which is how a cancelled
            // multi-version preparation used to index every remaining version
            // to the end. A refused submission means the calling task was
            // cancelled; throwing here is what makes the group cancel and
            // drain its in-flight children and the call fail as a whole
            // (returning `results` with holes would trap on the unwrap below).
            var started = 0
            while started < window, let (index, element) = pending.next() {
                guard group.addTaskUnlessCancelled(operation: { (index, try await transform(element)) }) else {
                    throw CancellationError()
                }
                started += 1
            }

            while let (index, result) = try await group.next() {
                results[index] = result
                if let (nextIndex, nextElement) = pending.next() {
                    guard group.addTaskUnlessCancelled(operation: { (nextIndex, try await transform(nextElement)) }) else {
                        throw CancellationError()
                    }
                }
            }

            return results.map { result in
                // Every index is filled once `next()` returns nil without
                // throwing: each submitted task reports exactly one index, and
                // a refused submission threw above.
                result!
            }
        }
    }
}
