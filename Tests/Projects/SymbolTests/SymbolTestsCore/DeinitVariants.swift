import Foundation

public enum DeinitVariants {
    public class SimpleDeinitTest {
        public var value: Int = 0
        public init() {}
        deinit {}
    }

    public class DeinitWithWorkTest {
        public var resource: Int = 0
        public init() {}
        deinit {
            resource = 0
        }
    }

    public actor ActorDeinitTest {
        public var state: Int = 0
        public init() {}
        deinit {}
    }

    public class GenericDeinitTest<Element> {
        public var element: Element
        public init(element: Element) {
            self.element = element
        }
        deinit {}
    }
}
