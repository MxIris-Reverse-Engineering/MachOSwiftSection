import Foundation

public enum DependentTypeAccess {
    public protocol DependentProtocol {
        associatedtype First
        associatedtype Second: Collection where Second.Element == First
    }

    public struct DependentAccessTest<Element: Collection> {
        public var iteratorElement: Element.Iterator.Element?
        public var indicesIndex: Element.Indices.Element?
        public var subSequenceIndex: Element.SubSequence.Index?

        public init(
            iteratorElement: Element.Iterator.Element?,
            indicesIndex: Element.Indices.Element?,
            subSequenceIndex: Element.SubSequence.Index?
        ) {
            self.iteratorElement = iteratorElement
            self.indicesIndex = indicesIndex
            self.subSequenceIndex = subSequenceIndex
        }
    }

    public struct DeepDependentAccessTest<Element: Collection> where Element.SubSequence: Collection {
        public var deepElement: Element.SubSequence.SubSequence.Element?

        public init(deepElement: Element.SubSequence.SubSequence.Element?) {
            self.deepElement = deepElement
        }
    }

    public struct DependentFunctionTest {
        public func acceptDependent<Element: Collection>(
            _ element: Element,
            iteratorElement: Element.Iterator.Element,
            indicesElement: Element.Indices.Element
        ) -> Element.SubSequence {
            element[element.startIndex..<element.endIndex]
        }
    }
}
