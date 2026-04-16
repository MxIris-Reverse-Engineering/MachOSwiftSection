public enum Frozen {
    @frozen
    public struct FrozenTest {
        public var x: Int
        public var y: Double

        public init(x: Int, y: Double) {
            self.x = x
            self.y = y
        }
    }

    @frozen
    public enum FrozenEnumTest {
        case empty
        case integer(Int)
        case string(String)
        case pair(Int, Double)
    }

    public struct InlinableMethodTest {
        public var value: Int

        public init(value: Int) {
            self.value = value
        }

        @inlinable
        public func doubled() -> Int {
            value * 2
        }

        @inlinable
        public func added(_ other: Int) -> Int {
            value + other
        }
    }

    @usableFromInline
    struct UsableFromInlineType {
        @usableFromInline
        var field: Int

        @usableFromInline
        init(field: Int) {
            self.field = field
        }

        @usableFromInline
        func method() -> Int {
            field
        }
    }
}
