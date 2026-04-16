import Foundation

public enum MetatypeUsage {
    public struct MetatypeFieldTest {
        public var concreteMetatype: Int.Type
        public var anyMetatype: Any.Type
        public var protocolMetatype: any Protocols.ProtocolTest.Type
        public var anyObjectMetatype: AnyObject.Type

        public init(
            concreteMetatype: Int.Type,
            anyMetatype: Any.Type,
            protocolMetatype: any Protocols.ProtocolTest.Type,
            anyObjectMetatype: AnyObject.Type
        ) {
            self.concreteMetatype = concreteMetatype
            self.anyMetatype = anyMetatype
            self.protocolMetatype = protocolMetatype
            self.anyObjectMetatype = anyObjectMetatype
        }
    }

    public struct MetatypeFunctionTest {
        public func acceptMetatype<Element>(_ type: Element.Type) -> Element.Type {
            type
        }

        public func acceptProtocolMetatype(_ type: any Protocols.ProtocolTest.Type) -> String {
            String(describing: type)
        }

        public func returnMetatype() -> Self.Type {
            Self.self
        }

        public func dynamicType<Element>(of value: Element) -> Element.Type {
            type(of: value)
        }
    }
}
