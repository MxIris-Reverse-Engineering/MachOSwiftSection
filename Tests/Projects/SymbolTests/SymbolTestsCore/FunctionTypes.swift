import Foundation

public enum FunctionTypes {
    public struct FunctionFieldTest {
        public var simpleFunction: (Int) -> Int
        public var multiArgumentFunction: (Int, String, Bool) -> Double
        public var throwingFunction: () throws -> Int
        public var asyncFunction: () async -> String
        public var asyncThrowingFunction: () async throws -> Int

        public init(
            simpleFunction: @escaping (Int) -> Int,
            multiArgumentFunction: @escaping (Int, String, Bool) -> Double,
            throwingFunction: @escaping () throws -> Int,
            asyncFunction: @escaping () async -> String,
            asyncThrowingFunction: @escaping () async throws -> Int
        ) {
            self.simpleFunction = simpleFunction
            self.multiArgumentFunction = multiArgumentFunction
            self.throwingFunction = throwingFunction
            self.asyncFunction = asyncFunction
            self.asyncThrowingFunction = asyncThrowingFunction
        }
    }

    public struct HigherOrderFunctionTest {
        public func acceptFunctionReturningFunction(_ producer: @escaping (Int) -> (Double) -> String) -> String {
            producer(0)(0.0)
        }

        public func returnFunctionReturningFunction() -> (Int) -> (Double) -> String {
            { _ in { _ in "" } }
        }

        public func curriedFunction(_ firstArgument: Int) -> (Double) -> (String) -> Bool {
            { _ in { _ in false } }
        }
    }

    public struct FunctionTypealiasTest {
        public typealias Transformer<Input, Output> = (Input) -> Output
        public typealias Predicate<Value> = (Value) -> Bool
        public typealias BiFunction<First, Second, Result> = (First, Second) -> Result

        public var transformer: Transformer<Int, String>
        public var predicate: Predicate<Int>
        public var biFunction: BiFunction<Int, String, Bool>

        public init(
            transformer: @escaping Transformer<Int, String>,
            predicate: @escaping Predicate<Int>,
            biFunction: @escaping BiFunction<Int, String, Bool>
        ) {
            self.transformer = transformer
            self.predicate = predicate
            self.biFunction = biFunction
        }
    }
}
