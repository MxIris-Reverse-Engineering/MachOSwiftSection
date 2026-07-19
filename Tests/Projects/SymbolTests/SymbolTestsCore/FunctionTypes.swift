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

    /// An optional thick function must stay 16 bytes (the function-pointer
    /// word carries the saturated extra-inhabitant count, so `.none` costs no
    /// tag byte) and the trailing marker must land at offset 16 — the shape
    /// that regresses to offset 17/size 24 if the thick function's extra
    /// inhabitants are dropped to zero.
    public struct OptionalFunctionFieldTest {
        public var callback: ((Int) -> Int)?
        public var trailingMarker: Int8

        public init(callback: ((Int) -> Int)?, trailingMarker: Int8) {
            self.callback = callback
            self.trailingMarker = trailingMarker
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
