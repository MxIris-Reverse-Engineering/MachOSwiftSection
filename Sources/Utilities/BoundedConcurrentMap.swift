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
    /// The first failure is rethrown. Elements not yet started never start;
    /// transforms already in flight run to completion first (a task group
    /// waits for its children), and their results are discarded.
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

            var started = 0
            while started < window, let (index, element) = pending.next() {
                group.addTask { (index, try await transform(element)) }
                started += 1
            }

            while let (index, result) = try await group.next() {
                results[index] = result
                if let (nextIndex, nextElement) = pending.next() {
                    group.addTask { (nextIndex, try await transform(nextElement)) }
                }
            }

            return results.map { result in
                // Every index is filled once `next()` returns nil without
                // throwing: each submitted task reports exactly one index.
                result!
            }
        }
    }
}
