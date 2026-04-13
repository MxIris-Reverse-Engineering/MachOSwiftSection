import Foundation

public enum AssociatedTypeWitnessPatterns {
    public protocol AssociatedPatternProtocol {
        associatedtype First
        associatedtype Second: Collection
        associatedtype Third
        associatedtype Fourth
        associatedtype Fifth
    }

    public struct ConcreteWitnessTest: AssociatedPatternProtocol {
        public typealias First = Int
        public typealias Second = [String]
        public typealias Third = Double
        public typealias Fourth = Bool
        public typealias Fifth = Character
    }

    public struct NestedWitnessTest: AssociatedPatternProtocol {
        public struct NestedFirst {}
        public struct NestedThird {}

        public typealias First = NestedFirst
        public typealias Second = [NestedFirst]
        public typealias Third = NestedThird
        public typealias Fourth = (NestedFirst, NestedThird)
        public typealias Fifth = NestedFirst?
    }

    public struct GenericParameterWitnessTest<Element>: AssociatedPatternProtocol {
        public typealias First = Element
        public typealias Second = [Element]
        public typealias Third = Element?
        public typealias Fourth = (Element, Element)
        public typealias Fifth = [String: Element]
    }

    public struct RecursiveWitnessTest: AssociatedPatternProtocol {
        public typealias First = RecursiveWitnessTest
        public typealias Second = [RecursiveWitnessTest]
        public typealias Third = RecursiveWitnessTest?
        public typealias Fourth = (RecursiveWitnessTest, RecursiveWitnessTest)
        public typealias Fifth = [String: RecursiveWitnessTest]
    }

    public struct DependentWitnessTest<Element: Collection>: AssociatedPatternProtocol {
        public typealias First = Element.Element
        public typealias Second = Element
        public typealias Third = Element.Iterator
        public typealias Fourth = Element.Index
        public typealias Fifth = Element.SubSequence
    }
}
