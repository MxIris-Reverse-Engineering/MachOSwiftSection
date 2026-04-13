import Foundation

public enum SameTypeRequirements {
    public struct SameTypeElementTest<First: Sequence, Second: Sequence> where First.Element == Second.Element {
        public var first: First
        public var second: Second

        public init(first: First, second: Second) {
            self.first = first
            self.second = second
        }
    }

    public struct NestedSameTypeTest<
        First: Collection,
        Second: Collection
    > where First.Element == Second.Element, First.Index == Int, Second.Index == Int {
        public var first: First
        public var second: Second

        public init(first: First, second: Second) {
            self.first = first
            self.second = second
        }
    }

    public struct ChainedSameTypeTest<
        First: Protocols.ProtocolTest,
        Second: Protocols.ProtocolTest,
        Third: Protocols.ProtocolTest
    > where First.Body == Second, Second.Body == Third {
        public var first: First
        public var second: Second
        public var third: Third

        public init(first: First, second: Second, third: Third) {
            self.first = first
            self.second = second
            self.third = third
        }
    }
}
