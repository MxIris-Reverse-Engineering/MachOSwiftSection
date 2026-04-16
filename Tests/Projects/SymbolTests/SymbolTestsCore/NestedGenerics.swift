import Foundation

public enum NestedGenerics {
    public struct OuterGenericTest<Outer> {
        public struct InnerGenericTest<Inner> {
            public struct InnerMostGenericTest<InnerMost> {
                public var outer: Outer
                public var inner: Inner
                public var innerMost: InnerMost

                public init(outer: Outer, inner: Inner, innerMost: InnerMost) {
                    self.outer = outer
                    self.inner = inner
                    self.innerMost = innerMost
                }
            }
        }
    }

    public struct NestedGenericWithConstraintsTest<Outer: Comparable> {
        public struct InnerConstrainedTest<Inner: Hashable> where Outer: Sendable {
            public var outer: Outer
            public var inner: Inner

            public init(outer: Outer, inner: Inner) {
                self.outer = outer
                self.inner = inner
            }
        }
    }

    public struct NestedTypealiasGenericTest<Element> {
        public typealias ElementArray = [Element]
        public typealias ElementDictionary<Key: Hashable> = [Key: Element]

        public var elements: ElementArray

        public init(elements: ElementArray) {
            self.elements = elements
        }
    }
}
