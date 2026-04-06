import Dispatch

extension Array where Element: Sendable {
    /// Transforms each element in parallel using `DispatchQueue.concurrentPerform`,
    /// preserving the original order.
    ///
    /// - Parameter transform: A closure that converts an `Element` to a `Result`.
    ///   Called from multiple threads concurrently — must be safe for concurrent execution.
    /// - Returns: An array of transformed results in the same order as the source.
    public func concurrentMap<Result>(_ transform: @Sendable (Element) -> Result) -> [Result] {
        guard !isEmpty else { return [] }

        let buffer = UnsafeMutableBufferPointer<Result>.allocate(capacity: count)
        defer {
            _ = buffer.deinitialize()
            buffer.deallocate()
        }

        nonisolated(unsafe) let base = buffer.baseAddress!
        let source = self

        DispatchQueue.concurrentPerform(iterations: count) { index in
            (base + index).initialize(to: transform(source[index]))
        }

        return Array<Result>(buffer)
    }

    /// Transforms each element in parallel, returning optional results.
    ///
    /// Unlike `concurrentMap`, failures (nil results) are represented in-place,
    /// preserving index correspondence with the source array.
    ///
    /// - Parameter transform: A closure that converts an `Element` to an optional `Result`.
    ///   Called from multiple threads concurrently — must be safe for concurrent execution.
    /// - Returns: An array of optional results in the same order as the source.
    public func concurrentMap<Result>(_ transform: @Sendable (Element) -> Result?) -> [Result?] {
        guard !isEmpty else { return [] }

        let buffer = UnsafeMutableBufferPointer<Result?>.allocate(capacity: count)
        buffer.initialize(repeating: nil)
        defer {
            _ = buffer.deinitialize()
            buffer.deallocate()
        }

        nonisolated(unsafe) let base = buffer.baseAddress!
        let source = self

        DispatchQueue.concurrentPerform(iterations: count) { index in
            (base + index).pointee = transform(source[index])
        }

        return Array<Result?>(buffer)
    }
}
