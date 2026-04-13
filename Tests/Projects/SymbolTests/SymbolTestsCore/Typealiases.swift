import Foundation

public enum Typealiases {
    public typealias IntegerAlias = Int
    public typealias CompletionHandler = (Int, Error?) -> Void
    public typealias ResultHandler<Value> = (Result<Value, Error>) -> Void
    public typealias EquatablePair<Element: Equatable> = (left: Element, right: Element)

    public struct TypealiasContainerTest<Element> {
        public typealias NestedAlias = Element
        public typealias NestedCollection = Array<Element>
        public typealias NestedHandler = (Element) -> Void

        public var element: NestedAlias
        public var collection: NestedCollection
        public var handler: NestedHandler

        public init(element: NestedAlias, collection: NestedCollection, handler: @escaping NestedHandler) {
            self.element = element
            self.collection = collection
            self.handler = handler
        }
    }

    public struct ConstrainedTypealiasTest<Element> where Element: Comparable {
        public typealias ConstrainedRange = ClosedRange<Element>
        public var range: ConstrainedRange

        public init(range: ConstrainedRange) {
            self.range = range
        }
    }
}
