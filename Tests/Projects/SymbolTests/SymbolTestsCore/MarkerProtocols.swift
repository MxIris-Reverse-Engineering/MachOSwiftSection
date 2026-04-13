import Foundation

public enum MarkerProtocols {
    public protocol MarkerProtocolTest {}

    public protocol EmptyMarkerProtocolTest {}

    public protocol ClassBoundMarkerProtocol: AnyObject {}

    public protocol InheritingMarkerProtocol: MarkerProtocolTest {}

    public struct MarkerConformingStructTest: MarkerProtocolTest, EmptyMarkerProtocolTest {
        public var value: Int
        public init(value: Int) {
            self.value = value
        }
    }

    public class MarkerConformingClassTest: ClassBoundMarkerProtocol, InheritingMarkerProtocol {
        public var label: String
        public init(label: String) {
            self.label = label
        }
    }

    public enum MarkerConformingEnumTest: MarkerProtocolTest {
        case first
        case second
    }
}
