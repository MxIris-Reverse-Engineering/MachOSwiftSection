import Foundation

public enum FunctionFeatures {
    public struct InoutFunctionTest {
        public var value: Int

        public mutating func increment() {
            value += 1
        }

        public static func swap(_ left: inout Int, _ right: inout Int) {
            let temporary = left
            left = right
            right = temporary
        }

        public static func modify(_ value: inout Int, by amount: Int) {
            value += amount
        }
    }

    public class ClosureParameterTest {
        public var storedCallbacks: [() -> Void] = []

        public func acceptEscaping(_ callback: @escaping () -> Void) {
            storedCallbacks.append(callback)
        }

        public func acceptAutoclosure(_ condition: @autoclosure () -> Bool) -> Bool {
            condition()
        }

        public func acceptEscapingAutoclosure(_ condition: @escaping @autoclosure () -> Bool) {
            storedCallbacks.append({ _ = condition() })
        }
    }

    /// Fixture for the `consuming` parameter modifier path
    /// (mangling: `n` → demangler `.owned` → printed as `consuming`).
    ///
    /// Notes on what this fixture can and cannot cover:
    ///
    /// - `consuming` on a free function or method parameter IS mangled
    ///   (as `n`). All four entries below produce `.owned` nodes in the
    ///   demangle tree and therefore round-trip through the printer.
    /// - `borrowing` on a parameter is **never** mangled by the Swift
    ///   compiler — its mangled name is byte-identical to a parameter
    ///   with no ownership modifier at all (verified empirically with
    ///   `swiftc` + `nm` for both class- and struct-typed parameters).
    ///   So a `borrowing` fixture would produce no `.shared` node and
    ///   would not exercise the printer path. The `.shared`-printed-as-
    ///   `borrowing` route is reached only via legacy `__shared`
    ///   spellings (e.g. `Foundation.String.init(format: __shared
    ///   String, ...)`), which are already covered by the dyld-cache
    ///   snapshot tests, not by SymbolTestsCore.
    /// - `init` parameters do not mangle `consuming` either (see
    ///   roadmap P1-7 ABI limitation). Hence only methods and a
    ///   `static` method here.
    public struct OwnershipParameterTest {
        public class Box {
            public var value: Int
            public init(_ value: Int) { self.value = value }
        }

        public func consumeBox(_ box: consuming Box) {
            _ = box
        }

        public func consumeWithLabel(_ box: consuming Box, label: Int) {
            _ = box
            _ = label
        }

        public func twoConsuming(_ first: consuming Box, _ second: consuming Box) {
            _ = first
            _ = second
        }

        public static func staticConsume(_ box: consuming Box) {
            _ = box
        }
    }

    public struct VariadicFunctionTest {
        public func sum(_ values: Int...) -> Int {
            values.reduce(0, +)
        }

        public func format(_ format: String, _ arguments: any CVarArg...) -> String {
            String(format: format, arguments: arguments)
        }
    }

    public struct ConventionFunctionTest {
        public func acceptCFunction(_ callback: @convention(c) (Int32, Int32) -> Int32) -> Int32 {
            callback(1, 2)
        }

        public func acceptBlockFunction(_ callback: @convention(block) (Int32) -> Int32) -> Int32 {
            callback(1)
        }

        public typealias CFunction = @convention(c) (Int32) -> Void

        public typealias BlockFunction = @convention(block) () -> NSObject?
    }

    public struct ExistentialAndMetatypeTest {
        public func acceptExistential(_ value: any Protocols.ProtocolTest) {}

        public func returnExistential() -> any Protocols.ProtocolTest & Sendable {
            Structs.StructTest()
        }

        public func acceptMetatype(_ type: Any.Type) -> String {
            String(describing: type)
        }

        public func acceptProtocolMetatype(_ type: (any Protocols.ProtocolTest).Type) -> Bool {
            false
        }

        public func acceptExistentialCollection(_ values: [any Protocols.ProtocolTest]) -> Int {
            values.count
        }

        public func acceptComposition(_ value: any Protocols.ProtocolTest & Sendable) {}
    }

    public struct FailableInitTest {
        public let value: Int

        public init?(value: Int) {
            guard value >= 0 else { return nil }
            self.value = value
        }

        public init!(unsafeValue: Int) {
            self.value = unsafeValue
        }
    }

    public struct MainActorClosureTest {
        public func acceptMainActorClosure(_ callback: @MainActor () -> Void) {}
        public func acceptMainActorAsync(_ callback: @MainActor () async -> Void) {}
    }

    public struct DefaultParameterFunctionTest {
        public func defaultMethod(value: Int = 0, label: String = "default", flag: Bool = true) -> String {
            label
        }

        public static func staticDefault(first: Int = 0, second: Int = 1) -> Int {
            first + second
        }
    }
}
