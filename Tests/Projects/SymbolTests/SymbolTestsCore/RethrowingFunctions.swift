import Foundation

public enum RethrowingFunctions {
    public struct RethrowingHolderTest {
        public func rethrowing(_ body: () throws -> Int) rethrows -> Int {
            try body()
        }

        public func asyncRethrowing(_ body: () async throws -> Int) async rethrows -> Int {
            try await body()
        }

        public func rethrowingMap<Element>(_ elements: [Element], transform: (Element) throws -> Int) rethrows -> [Int] {
            try elements.map(transform)
        }

        public func rethrowingWithDefault(_ body: () throws -> Int, defaultValue: Int = 0) rethrows -> Int {
            try body()
        }

        public func rethrowingGeneric<Input, Output>(_ input: Input, transform: (Input) throws -> Output) rethrows -> Output {
            try transform(input)
        }
    }
}
