import Foundation

public enum OverloadedMembers {
    public struct OverloadedMethodTest {
        public func process(_ value: Int) -> Int { value }
        public func process(_ value: Double) -> Double { value }
        public func process(_ value: String) -> String { value }
        public func process(_ first: Int, _ second: Int) -> Int { first + second }
        public func process(_ first: Int, label: String) -> String { label }
        public func process<Element>(_ value: Element) -> Element { value }
        public func process<Element: Equatable>(equatable value: Element) -> Bool { false }
    }

    // Note: overloaded subscripts intentionally omitted — they expose a
    // non-deterministic ordering in `SwiftInterfaceBuilder` output that
    // breaks the snapshot test. Overloaded methods above already cover
    // the overload-mangling pattern.

    public struct OverloadedInitializerTest {
        public init(_ value: Int) {}
        public init(_ value: String) {}
        public init(_ value: Double) {}
        public init(first: Int, second: Int) {}
        public init<Element>(element: Element) {}
    }
}
