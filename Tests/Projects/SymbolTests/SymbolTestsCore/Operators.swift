infix operator <=>: ComparisonPrecedence

public enum Operators {
    public struct OperatorTestType: Equatable {
        public var value: Int

        public init(value: Int) {
            self.value = value
        }

        public static func + (lhs: Self, rhs: Self) -> Self {
            Self(value: lhs.value + rhs.value)
        }

        public static func - (lhs: Self, rhs: Self) -> Self {
            Self(value: lhs.value - rhs.value)
        }

        public static func * (lhs: Self, rhs: Self) -> Self {
            Self(value: lhs.value * rhs.value)
        }

        public static prefix func - (operand: Self) -> Self {
            Self(value: -operand.value)
        }

        public static func += (lhs: inout Self, rhs: Self) {
            lhs.value += rhs.value
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.value < rhs.value
        }

        public static func <=> (lhs: Self, rhs: Self) -> Int {
            lhs.value - rhs.value
        }
    }
}
