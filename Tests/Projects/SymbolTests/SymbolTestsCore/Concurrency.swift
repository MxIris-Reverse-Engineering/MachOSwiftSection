import Foundation

public enum Concurrency {
    public struct AsyncFunctionTest {
        public func asyncFunction() async -> Int { 0 }

        public func throwsFunction() throws -> Int { 0 }

        public func asyncThrowsFunction() async throws -> Int { 0 }
    }

    public struct TypedThrowsErrorTest: Error, Sendable {
        public var message: String
    }

    public struct TypedThrowsFunctionTest {
        public func typedThrowsFunction() throws(TypedThrowsErrorTest) -> Int { 0 }

        public func asyncTypedThrowsFunction() async throws(TypedThrowsErrorTest) -> Int { 0 }
    }

    public struct SendableClosureTest {
        public var sendableClosure: @Sendable () -> Void

        public func acceptSendable(_ closure: @Sendable () -> Void) {}

        public func acceptSendableAsync(_ closure: @Sendable () async -> Void) {}

        public func acceptSendableThrows(_ closure: @Sendable () throws -> Void) {}
    }

    public struct SendableTest: Sendable {
        public var value: Int

        public var name: String
    }
}
