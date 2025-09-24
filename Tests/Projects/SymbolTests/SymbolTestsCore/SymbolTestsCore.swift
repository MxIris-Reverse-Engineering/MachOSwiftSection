import Foundation

@available(macOS 15.0, *)
@_originallyDefinedIn(module: "SymbolTests", macOS 26.0)
public struct TestsValues {}

public final class TestsObjects {}

public protocol TestBody { }

public protocol Test<Body> {
    associatedtype Body: TestBody

    var body: Body { get }
}

public struct ModuleTest: Test {
    public var body: some TestBody {
        fatalError()
    }
}

extension Never: TestBody {}
