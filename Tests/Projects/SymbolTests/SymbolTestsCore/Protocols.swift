import Foundation

public enum Protocols {
    public protocol ProtocolTest<Body> {
        associatedtype Body: ProtocolTest

        var body: Body { get }

        static var body: Body? { get }
    }

    public protocol ProtocolWitnessTableTest {
        func a()
        func b()
        func c()
        func d()
        func e()
    }

    public protocol TestCollection<Element> {
        associatedtype Element
    }

    public protocol BaseProtocolTest {
        func baseMethod() -> String
    }

    public protocol DerivedProtocolTest: BaseProtocolTest {
        func derivedMethod() -> Int
    }

    public protocol ClassBoundProtocolTest: AnyObject {
        var classProperty: Int { get set }
        func classMethod()
    }

    public protocol ObjCInheritingProtocolTest: NSObjectProtocol {
        func swiftMethod() -> String
    }

    public protocol MultiInheritanceProtocolTest: BaseProtocolTest, ProtocolTest {
        func multiMethod()
    }

    public protocol ProtocolWithInitTest {
        init()
        init(value: Int)
    }

    public protocol ProtocolWithSubscriptTest {
        subscript(index: Int) -> String { get }
    }

    public protocol ProtocolWithReadWriteSubscriptTest {
        subscript(key: String) -> Int { get set }
    }

    public protocol ProtocolWithStaticTest {
        static var staticProperty: Int { get }
        static func staticMethod() -> Self
    }
}

extension Protocols.ProtocolTest {
    public static var body: Body? { nil }

    public static func test(lhs: Body, rhs: Self) -> Bool { false }
}

extension Array: Protocols.TestCollection {}
