public enum Noncopyable {
    public struct NoncopyableTest: ~Copyable {
        public var value: Int

        public init(value: Int) {
            self.value = value
        }

        public consuming func consume() -> Int {
            value
        }

        public borrowing func borrow() -> Int {
            value
        }

        public mutating func mutate() {
            value += 1
        }

        deinit {}
    }

    public enum NoncopyableEnumTest: ~Copyable {
        case value(Int)
        case empty

        public consuming func unwrap() -> Int {
            switch self {
            case .value(let result):
                return result
            case .empty:
                return 0
            }
        }
    }

    public struct NoncopyableGenericTest<T: ~Copyable>: ~Copyable {
        public let value: T

        public init(value: consuming T) {
            self.value = value
        }
    }
}
