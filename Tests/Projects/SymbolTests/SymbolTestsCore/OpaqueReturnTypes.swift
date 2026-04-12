public enum OpaqueReturnTypes {
    public struct OpaqueReturnTypeTest {
        public struct AnyProtocolTest<A: Protocols.ProtocolTest, B: Protocols.ProtocolTest>: Protocols.ProtocolTest where A.Body == Generics.GenericRequirementTest<B>, A.Body.Body.Body == B {
            public var body: A { fatalError() }
        }

        public var variable: some Sequence<any Equatable> { [] }

        public func function<A: Protocols.ProtocolTest>() -> some Sequence<A> { [] }

        public func functionOptional<A: Protocols.ProtocolTest>() -> (some Sequence<A>)? { [] }

        public func functionTuple<A: Protocols.ProtocolTest>() -> (some Sequence<A>, A?) { ([], nil) }

        public func functionWhere<A: Protocols.ProtocolTest, B: Protocols.ProtocolTest>() -> (some Sequence<A>, (some Protocols.ProtocolTest<A>)?, some Collection<A>)? where A.Body == Generics.GenericRequirementTest<B>, A.Body.Body.Body == B { ([], AnyProtocolTest<A, B>(), []) }

        public func functionNested<A: Protocols.ProtocolTest & Equatable, B: Protocols.ProtocolTest & Equatable>(_: A, _: B) -> (some Sequence<[A]> & Equatable, (some Protocols.ProtocolTest<A>)?, some Collection<[A]> & Protocols.TestCollection<[A]> & Equatable)? where A.Body == Generics.GenericRequirementTest<B>, A.Body.Body.Body == B { ([], AnyProtocolTest<A, B>(), []) }
    }

    public protocol ProtocolPrimaryAssociatedTypeTest<First, Second> {
        associatedtype First: Protocols.ProtocolTest
        associatedtype Second: Protocols.ProtocolTest where Second.Body.Body.Body.Body.Body.Body == First.Body.Body.Body.Body.Body.Body
    }

    public enum ProtocolPrimaryAssociatedTypeFirst: Protocols.ProtocolTest {
        public var body: ProtocolPrimaryAssociatedTypeFirst { fatalError() }
    }

    public enum ProtocolPrimaryAssociatedTypeSecond: Protocols.ProtocolTest {
        public var body: ProtocolPrimaryAssociatedTypeFirst { fatalError() }
    }

    public enum UnderlyingPrimaryAssociatedTypeTest<First: Protocols.ProtocolTest, Second: Protocols.ProtocolTest>: ProtocolPrimaryAssociatedTypeTest where Second.Body.Body.Body.Body.Body.Body == First.Body.Body.Body.Body.Body.Body {
        case none
    }

    public struct OpaquePrimaryAssociatedTypeReturnTypeTest {
        public var body: some ProtocolPrimaryAssociatedTypeTest<ProtocolPrimaryAssociatedTypeFirst, ProtocolPrimaryAssociatedTypeSecond> {
            UnderlyingPrimaryAssociatedTypeTest<ProtocolPrimaryAssociatedTypeFirst, ProtocolPrimaryAssociatedTypeSecond>.none
        }
    }
}
