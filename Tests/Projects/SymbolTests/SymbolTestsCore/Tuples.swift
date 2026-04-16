import Foundation

public enum Tuples {
    public struct TupleFieldTest {
        public var namedTuple: (first: Int, second: String)
        public var unnamedTuple: (Int, Double, Bool)
        public var nestedTuple: ((Int, Int), (String, String))

        public init(
            namedTuple: (first: Int, second: String),
            unnamedTuple: (Int, Double, Bool),
            nestedTuple: ((Int, Int), (String, String))
        ) {
            self.namedTuple = namedTuple
            self.unnamedTuple = unnamedTuple
            self.nestedTuple = nestedTuple
        }
    }

    public struct TupleFunctionTest {
        public func acceptTuple(_ value: (Int, String)) -> (Bool, Double) {
            (true, 0.0)
        }

        public func acceptNamedTuple(_ value: (identifier: Int, label: String)) -> (result: Bool, score: Double) {
            (result: true, score: 0.0)
        }

        public func returnLargeTuple() -> (Int, Double, String, Bool, Int, Double) {
            (0, 0.0, "", true, 0, 0.0)
        }
    }

    public struct GenericTupleTest<First, Second> {
        public var pair: (First, Second)
        public var labeled: (left: First, right: Second)

        public init(pair: (First, Second), labeled: (left: First, right: Second)) {
            self.pair = pair
            self.labeled = labeled
        }
    }
}
