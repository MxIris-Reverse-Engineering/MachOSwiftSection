import Foundation

public enum GenericRequirementVariants {
    public struct ProtocolRequirementTest<Element: Protocols.ProtocolTest> {
        public var element: Element
        public init(element: Element) { self.element = element }
    }

    public struct SameTypeRequirementTest<First, Second> where First == Second {
        public var first: First
        public var second: Second

        public init(first: First, second: Second) {
            self.first = first
            self.second = second
        }
    }

    public class GenericBaseClassForRequirementTest {
        public var baseField: Int = 0
        public init() {}
    }

    public struct BaseClassRequirementTest<Element: GenericBaseClassForRequirementTest> {
        public var element: Element
        public init(element: Element) { self.element = element }
    }

    public struct LayoutAnyObjectRequirementTest<Element: AnyObject> {
        public var element: Element
        public init(element: Element) { self.element = element }
    }

    public struct ParameterPackRequirementTest<each Element> {
        public var elements: (repeat each Element)

        public init(elements: (repeat each Element)) {
            self.elements = elements
        }
    }

    public struct ConstrainedParameterPackTest<each Element: Protocols.ProtocolTest> {
        public var elements: (repeat each Element)

        public init(elements: (repeat each Element)) {
            self.elements = elements
        }
    }

    public struct InvertibleProtocolRequirementTest<Element: ~Copyable>: ~Copyable {
        public var element: Element

        public init(element: consuming Element) {
            self.element = element
        }
    }
}
