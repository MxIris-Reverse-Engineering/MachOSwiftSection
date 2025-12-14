import Foundation
import SymbolTestsHelper

@available(macOS 15.0, *)
@_originallyDefinedIn(module: "SymbolTests", macOS 26.0)
public struct TestsValues {}

public final class TestsObjects {}

public enum MultiPayloadEnumTests {
    case closure(() -> Void)
    case object(NSObject)
    case tuple(a: Int, b: Double)
    case empty
}

public protocol ProtocolTest<Body> {
    associatedtype Body: ProtocolTest

    var body: Body { get }

    static var body: Body? { get }
}

extension ProtocolTest {
    public static var body: Body? { nil }

    public static func test(lhs: Body, rhs: Self) -> Bool { false }
}

private enum PrivateProtocolTest: ProtocolTest {
    case empty
    
    var body: some ProtocolTest {
        fatalError()
    }
    
    static var body: Body? {
        fatalError()
    }
}

public struct StructTest: ProtocolTest {
    
    public var body: some ProtocolTest {
        PrivateProtocolTest.empty
    }

    public static var body: some ProtocolTest {
        PrivateProtocolTest.empty
    }
}

public class ExternalSwiftSubclassTest: Object {
    public override func instanceMethod() -> String {
        "xxxxxxxxxxxxx"
    }
}

public class ExternalObjCSubclassTest: NSObject {
    public override func isKind(of aClass: AnyClass) -> Bool {
        return true
    }
}

public class ClassTest {
    public var instanceVariable: Bool {
        set {}
        get { false }
    }

    public func instanceMethod() -> Self { self }

    public dynamic var dynamicVariable: Bool {
        set {}
        get { false }
    }

    public dynamic func dynamicMethod() {}
}

public class SubclassTest: ClassTest {
    public override final var instanceVariable: Bool {
        set {}
        get { true }
    }

    public override func instanceMethod() -> Self { self }

    public override var dynamicVariable: Bool {
        set {}
        get { true }
    }

    public override func dynamicMethod() {}
}

public final class FinalClassTest: SubclassTest {
    public override func instanceMethod() -> Self { self }

    public override var dynamicVariable: Bool {
        set {}
        get { true }
    }

    public override func dynamicMethod() {}
}

public struct GenericRequirementTest<T: ProtocolTest>: ProtocolTest {
    public private(set) var content: T

    public init(content: T) {
        self.content = content
    }

    public var body: T {
        content
    }
}

extension GenericRequirementTest: RawRepresentable where T: RawRepresentable {
    public struct RawRepresentableNestedStruct {}

    public typealias RawValue = T

    public var rawValue: T { content }

    public init?(rawValue: T) {
        self.content = rawValue
    }
}

extension GenericRequirementTest: Equatable where T: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.content == rhs.content
    }
}

extension GenericRequirementTest {
    public static func test(lhs: T, rhs: Self) -> Bool { false }
}

extension GenericRequirementTest.RawRepresentableNestedStruct {
    public struct NestedStruct {}
}

extension GenericRequirementTest.RawRepresentableNestedStruct.NestedStruct {}

public struct GenericPackTest<V, each T, S>: ProtocolTest where repeat each T: ProtocolTest {
    var _content: (repeat each T)

    public var body: Never {
        fatalError()
    }
}

public struct GenericValueTest < A, let count: Int, C>: ProtocolTest {
    public var content: C

    public var body: Never {
        fatalError()
    }

    public func function(value: C) -> Bool { false }
}

public protocol TestCollection<Element> {
    associatedtype Element
}

extension Array: TestCollection {}

public struct OpaqueReturnTypeTest {
    public struct AnyProtocolTest<A: ProtocolTest, B: ProtocolTest>: ProtocolTest where A.Body == GenericRequirementTest<B>, A.Body.Body.Body == B {
        public var body: A { fatalError() }
    }

    public var variable: some Sequence<any Equatable> { [] }

    public func function<A: ProtocolTest>() -> some Sequence<A> { [] }

    public func functionOptional<A: ProtocolTest>() -> (some Sequence<A>)? { [] }

    public func functionTuple<A: ProtocolTest>() -> (some Sequence<A>, A?) { ([], nil) }

    public func functionWhere<A: ProtocolTest, B: ProtocolTest>() -> (some Sequence<A>, (some ProtocolTest<A>)?, some Collection<A>)? where A.Body == GenericRequirementTest<B>, A.Body.Body.Body == B { ([], AnyProtocolTest<A, B>(), []) }

    public func functionNested<A: ProtocolTest & Equatable, B: ProtocolTest & Equatable>(_: A, _: B) -> (some Sequence<[A]> & Equatable, (some ProtocolTest<A>)?, some Collection<[A]> & TestCollection<[A]> & Equatable)? where A.Body == GenericRequirementTest<B>, A.Body.Body.Body == B { ([], AnyProtocolTest<A, B>(), []) }
}

public protocol ProtocolPrimaryAssociatedTypeTest<First, Second> {
    associatedtype First: ProtocolTest
    associatedtype Second: ProtocolTest where Second.Body.Body.Body.Body.Body.Body == First.Body.Body.Body.Body.Body.Body
}

public enum ProtocolPrimaryAssociatedTypeFirst: ProtocolTest {
    public var body: ProtocolPrimaryAssociatedTypeFirst { fatalError() }
}

public enum ProtocolPrimaryAssociatedTypeSecond: ProtocolTest {
    public var body: ProtocolPrimaryAssociatedTypeFirst { fatalError() }
}

public enum UnderlyingPrimaryAssociatedTypeTest<First: ProtocolTest, Second: ProtocolTest>: ProtocolPrimaryAssociatedTypeTest where Second.Body.Body.Body.Body.Body.Body == First.Body.Body.Body.Body.Body.Body {
    case none
}

public struct OpaquePrimaryAssociatedTypeReturnTypeTest {
    public var body: some ProtocolPrimaryAssociatedTypeTest<ProtocolPrimaryAssociatedTypeFirst, ProtocolPrimaryAssociatedTypeSecond> {
        UnderlyingPrimaryAssociatedTypeTest<ProtocolPrimaryAssociatedTypeFirst, ProtocolPrimaryAssociatedTypeSecond>.none
    }
}

extension Never: ProtocolTest {
    public typealias Body = Never
    public var body: Body { fatalError() }
}

extension Never: @retroactive IteratorProtocol {
    public typealias Element = Never
    public mutating func next() -> Element? {
        fatalError()
    }
}

extension Never: @retroactive Sequence {
    public typealias Iterator = Never

    public func makeIterator() -> Iterator {
        fatalError()
    }
}

public typealias SpecializationGenericStructNonRequirement = GenericStructNonRequirement<String>

public struct GenericStructNonRequirement<A> {
    public var field1: Double
    public var field2: A
    public var field3: Int
}

public struct GenericStructLayoutRequirement<A: AnyObject> {
    public var field1: Double
    public var field2: A
    public var field3: Int
}

public class GenericClassNonRequirement<A> {
    public var field1: Double
    public var field2: A
    public var field3: Int

    public init(field1: Double, field2: A, field3: Int) {
        self.field1 = field1
        self.field2 = field2
        self.field3 = field3
    }
}

public class GenericClassLayoutRequirement<A: AnyObject> {
    public var field1: Double
    public var field2: A
    public var field3: Int

    public init(field1: Double, field2: A, field3: Int) {
        self.field1 = field1
        self.field2 = field2
        self.field3 = field3
    }
}

public class GenericClassNonRequirementInheritNSObject<A>: NSObject {
    public var field1: Double
    public var field2: A
    public var field3: Int

    public init(field1: Double, field2: A, field3: Int) {
        self.field1 = field1
        self.field2 = field2
        self.field3 = field3
    }
}

public class GenericClassLayoutRequirementInheritNSObject<A: AnyObject>: NSObject {
    public var field1: Double
    public var field2: A
    public var field3: Int

    public init(field1: Double, field2: A, field3: Int) {
        self.field1 = field1
        self.field2 = field2
        self.field3 = field3
    }
}

public protocol ProtocolWitnessTableTest {
    func a()
    func b()
    func c()
    func d()
    func e()
}

extension StructTest: ProtocolWitnessTableTest {
    public func a() {
        print(GenericStructNonRequirement<Self>(field1: 0.1, field2: self, field3: 1))
    }

    public func b() {}

    public func c() {}

    public func d() {}

    public func e() {}
}

public enum MultiPayloadEnumTests1 {
    case string(String)
    case data(Data)
    case nsNumber(Decimal)
    case date(Date)
    case url(URL)
    case attributedString(AttributedString)
}

public enum MultiPayloadEnumTests2 {
    case string(Swift.String)
    case data(Data)
    case nsNumber(NSNumber)
    case nsNumber1(NSNumber)
    case nsNumber2(NSNumber)
    case nsNumber3(NSNumber)
    case nsNumber4(NSNumber)
    case nsNumber5(NSNumber)
}
