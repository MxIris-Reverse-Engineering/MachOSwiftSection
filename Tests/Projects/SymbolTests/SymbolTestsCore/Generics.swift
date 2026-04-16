public enum Generics {
    public struct GenericRequirementTest<T: Protocols.ProtocolTest>: Protocols.ProtocolTest {
        public private(set) var content: T

        public init(content: T) {
            self.content = content
        }

        public var body: T {
            content
        }
    }

    public struct GenericPackTest<V, each T, S>: Protocols.ProtocolTest where repeat each T: Protocols.ProtocolTest {
        var _content: (repeat each T)

        public var body: Never {
            fatalError()
        }
    }

    public struct GenericValueTest<A, let count: Int, C>: Protocols.ProtocolTest {
        public var content: C

        public var body: Never {
            fatalError()
        }

        public func function(value: C) -> Bool { false }
    }

    public struct GenericNestedFunction<A, B> {
        let a: A
        let b: B

        public func function<A1, B1>(a: A1, b: B1) {}
    }
}

extension Generics.GenericRequirementTest: RawRepresentable where T: RawRepresentable {
    public struct RawRepresentableNestedStruct {}

    public typealias RawValue = T

    public var rawValue: T { content }

    public init?(rawValue: T) {
        self.content = rawValue
    }
}

extension Generics.GenericRequirementTest: Equatable where T: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.content == rhs.content
    }
}

extension Generics.GenericRequirementTest {
    public static func test(lhs: T, rhs: Self) -> Bool { false }
}

extension Generics.GenericRequirementTest.RawRepresentableNestedStruct {
    public struct NestedStruct {}
}

extension Generics.GenericRequirementTest.RawRepresentableNestedStruct.NestedStruct {}
