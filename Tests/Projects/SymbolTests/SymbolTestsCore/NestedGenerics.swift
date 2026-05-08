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

    /// Three-level nesting with one direct protocol constraint per level.
    /// Used as the fixture-side counter-example for the `currentRequirements`,
    /// `currentParameters`, `parentRequirements`, and `parentParameters`
    /// invariants — the cumulative parent storage at depth ≥ 2 is the trigger
    /// for the P0.1 / P0.2 / P0.3 bugs surfaced in `GenericSpecializer`.
    /// `InnerMostConstrainedTest`'s generic context surfaces:
    ///   - `parameters` (cumulative): [Outer, Middle, InnerMost]
    ///   - `requirements` (cumulative): [Outer:Hashable, Middle:Equatable, InnerMost:Comparable]
    ///   - `parentParameters[0]` (Outer cumulative): [Outer]
    ///   - `parentParameters[1]` (Middle cumulative): [Outer, Middle]
    public struct NestedGenericThreeLevelConstraintTest<Outer: Hashable> {
        public struct MiddleConstrainedTest<Middle: Equatable> {
            public struct InnerMostConstrainedTest<InnerMost: Comparable> {
                public var outer: Outer
                public var middle: Middle
                public var innerMost: InnerMost

                public init(outer: Outer, middle: Middle, innerMost: InnerMost) {
                    self.outer = outer
                    self.middle = middle
                    self.innerMost = innerMost
                }
            }
        }
    }
}
