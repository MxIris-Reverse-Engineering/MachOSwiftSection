import Foundation

public enum ExistentialAny {
    public struct ExistentialFieldTest {
        public var simpleExistential: any Protocols.ProtocolTest
        public var compositionExistential: any Protocols.ProtocolTest & Sendable
        public var optionalExistential: (any Protocols.ProtocolTest)?
        public var existentialArray: [any Protocols.ProtocolTest]
        public var existentialDictionary: [String: any Protocols.ProtocolTest]
        public var existentialFunction: (any Protocols.ProtocolTest) -> Void

        public init(
            simpleExistential: any Protocols.ProtocolTest,
            compositionExistential: any Protocols.ProtocolTest & Sendable,
            optionalExistential: (any Protocols.ProtocolTest)?,
            existentialArray: [any Protocols.ProtocolTest],
            existentialDictionary: [String: any Protocols.ProtocolTest],
            existentialFunction: @escaping (any Protocols.ProtocolTest) -> Void
        ) {
            self.simpleExistential = simpleExistential
            self.compositionExistential = compositionExistential
            self.optionalExistential = optionalExistential
            self.existentialArray = existentialArray
            self.existentialDictionary = existentialDictionary
            self.existentialFunction = existentialFunction
        }
    }

    public struct ExistentialClassBoundTest {
        public var classBound: any Protocols.ClassBoundProtocolTest
        public var anyObjectReference: AnyObject

        public init(classBound: any Protocols.ClassBoundProtocolTest, anyObjectReference: AnyObject) {
            self.classBound = classBound
            self.anyObjectReference = anyObjectReference
        }
    }
}
