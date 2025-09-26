import Foundation

@available(macOS 15.0, *)
@_originallyDefinedIn(module: "SymbolTests", macOS 26.0)
public struct TestsValues {}

public final class TestsObjects {}

public protocol Test<Body> {
    associatedtype Body: Test

    var body: Body { get }
}

public struct ModuleTest: Test {
    public var body: some Test {
        fatalError()
    }
}

extension Never: Test {
    public var body: some Test { fatalError() }
}

public struct GenericTest<T: Test>: Test {
    public var _content: T

    public init(_content: T) {
        self._content = _content
    }

    public var body: some Test {
        _content
    }
}

extension GenericTest: RawRepresentable where T: RawRepresentable {
    public typealias RawValue = T

    public var rawValue: T { _content }

    public init?(rawValue: T) {
        self._content = rawValue
    }
}

extension GenericTest: Equatable where T: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs._content == rhs._content
    }
}

extension GenericTest {
    public static func test(lhs: T, rhs: Self) -> Bool { false }
}

extension Test {
    public static func test(lhs: Body, rhs: Self) -> Bool { false }
}

public struct GenericPackTest<each T: Test> {
    var _content: (repeat each T)

    public var body: some Test {
        fatalError()
    }
}
