import Foundation

public enum CollectionConformances {
    public struct CustomSequenceTest: Sequence {
        public struct Iterator: IteratorProtocol {
            public mutating func next() -> Int? { nil }
        }

        public func makeIterator() -> Iterator {
            Iterator()
        }
    }

    public struct CustomCollectionTest: Collection {
        public var startIndex: Int { 0 }
        public var endIndex: Int { 0 }

        public subscript(position: Int) -> Int { 0 }

        public func index(after index: Int) -> Int {
            index + 1
        }
    }

    public struct CustomBidirectionalCollectionTest: BidirectionalCollection {
        public var startIndex: Int { 0 }
        public var endIndex: Int { 0 }

        public subscript(position: Int) -> String { "" }

        public func index(after index: Int) -> Int {
            index + 1
        }

        public func index(before index: Int) -> Int {
            index - 1
        }
    }

    public struct CustomRandomAccessCollectionTest: RandomAccessCollection {
        public var startIndex: Int { 0 }
        public var endIndex: Int { 0 }

        public subscript(position: Int) -> Double { 0.0 }

        public func index(after index: Int) -> Int {
            index + 1
        }

        public func index(before index: Int) -> Int {
            index - 1
        }
    }
}
