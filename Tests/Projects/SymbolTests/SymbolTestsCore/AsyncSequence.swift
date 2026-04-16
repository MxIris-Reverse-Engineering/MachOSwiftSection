import Foundation

public enum AsyncSequenceTests {
    public struct AsyncSequenceTest: AsyncSequence {
        public typealias Element = Int

        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async -> Element? {
                nil
            }
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator()
        }
    }

    public struct ThrowingAsyncSequenceTest: AsyncSequence {
        public typealias Element = String

        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async throws -> Element? {
                nil
            }
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator()
        }
    }

    public struct GenericAsyncSequenceTest<Element: Sendable>: AsyncSequence {
        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async -> Element? {
                nil
            }
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator()
        }
    }
}
