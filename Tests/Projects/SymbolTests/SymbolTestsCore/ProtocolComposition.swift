import Foundation

public enum ProtocolComposition {
    public protocol ComposeFirstProtocol {
        func first() -> Int
    }

    public protocol ComposeSecondProtocol {
        func second() -> String
    }

    public protocol ComposeThirdProtocol {
        func third() -> Double
    }

    public struct ProtocolCompositionFieldTest {
        public var twoComposition: any ComposeFirstProtocol & ComposeSecondProtocol
        public var threeComposition: any ComposeFirstProtocol & ComposeSecondProtocol & ComposeThirdProtocol
        public var classBoundComposition: any AnyObject & ComposeFirstProtocol
        public var sendableComposition: any Sendable & ComposeFirstProtocol

        public init(
            twoComposition: any ComposeFirstProtocol & ComposeSecondProtocol,
            threeComposition: any ComposeFirstProtocol & ComposeSecondProtocol & ComposeThirdProtocol,
            classBoundComposition: any AnyObject & ComposeFirstProtocol,
            sendableComposition: any Sendable & ComposeFirstProtocol
        ) {
            self.twoComposition = twoComposition
            self.threeComposition = threeComposition
            self.classBoundComposition = classBoundComposition
            self.sendableComposition = sendableComposition
        }
    }

    public struct ProtocolCompositionFunctionTest {
        public func acceptComposition(_ value: any ComposeFirstProtocol & ComposeSecondProtocol) {}

        public func returnComposition() -> any ComposeFirstProtocol & ComposeSecondProtocol {
            fatalError()
        }

        public func genericCompositionParameter<Element: ComposeFirstProtocol & ComposeSecondProtocol>(_ element: Element) {}
    }
}
