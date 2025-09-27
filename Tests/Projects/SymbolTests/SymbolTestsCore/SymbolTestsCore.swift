import Foundation

@available(macOS 15.0, *)
@_originallyDefinedIn(module: "SymbolTests", macOS 26.0)
public struct TestsValues {}

public final class TestsObjects {}

public protocol Test<Body> {
    associatedtype Body: Test

    var body: Body { get }
}

extension Test {
    public static func test(lhs: Body, rhs: Self) -> Bool { false }
}

extension Never: Test {
    public var body: some Test { self }
}

public struct NormalTest: Test {
    public var body: some Test {
        fatalError()
    }
}

public struct GenericRequirementTest<T: Test>: Test {
    public private(set) var content: T

    public init(content: T) {
        self.content = content
    }

    public var body: some Test {
        content
    }
}

extension GenericRequirementTest: RawRepresentable where T: RawRepresentable {
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

public struct GenericPackTest<V, each T, S>: Test where repeat each T: Test {
    var _content: (repeat each T)

    public var body: Never {
        fatalError()
    }
}

public struct GenericValueTest<A, let count: Int, C>: Test {
    public var content: C
    
    
    public var body: Never {
        fatalError()
    }
    
    public func function(value: C) -> Bool { false }
}

public class ClassTest {
    public func returnSelf() -> Self { self }
}
