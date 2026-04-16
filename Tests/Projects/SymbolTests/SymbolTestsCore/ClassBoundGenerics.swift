import Foundation

public enum ClassBoundGenerics {
    public struct AnyObjectBoundTest<Element: AnyObject> {
        public var element: Element
        public init(element: Element) {
            self.element = element
        }
    }

    public struct AnyObjectAndProtocolBoundTest<Element> where Element: AnyObject, Element: Protocols.ProtocolTest {
        public var element: Element
        public init(element: Element) {
            self.element = element
        }
    }

    public class ClassBoundGenericClassTest<Element: AnyObject> {
        public var element: Element
        public init(element: Element) {
            self.element = element
        }
    }

    public protocol ClassBoundGenericProtocol: AnyObject {
        associatedtype Item: AnyObject
        var item: Item { get }
    }

    public struct ClassBoundFunctionTest {
        public func acceptClassBound<Element: AnyObject>(_ element: Element) -> Element {
            element
        }

        public func acceptClassAndProtocol<Element>(_ element: Element) -> Element where Element: AnyObject, Element: Protocols.ProtocolTest {
            element
        }
    }
}
