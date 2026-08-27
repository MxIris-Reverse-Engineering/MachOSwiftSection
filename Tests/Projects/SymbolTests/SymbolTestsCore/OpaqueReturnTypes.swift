import SymbolTestsHelper

public enum OpaqueReturnTypes {
    public struct OpaqueReturnTypeTest {
        /// Opaque-attribution-proposal witnesses. The three protocols share one associated
        /// type name, so a single typealias witnesses them all — the opaque
        /// signatures below still pin only what their sugar spells out.
        public struct NameFallbackGuardWitness<CollectionElement>: Protocols.TestCollection, Protocols.UnpinnedElementProtocol, Equatable {
            public typealias Element = CollectionElement
        }

        public struct ModuleRefineClosureWitness: Protocols.ModuleRefinedProtocol, Equatable {
            public typealias Item = Int
        }

        public struct CrossImageRefineClosureWitness: HelperRefinedProtocol, Equatable {
            public typealias Item = Int
        }
        public struct AnyProtocolTest<A: Protocols.ProtocolTest, B: Protocols.ProtocolTest>: Protocols.ProtocolTest where A.Body == Generics.GenericRequirementTest<B>, A.Body.Body.Body == B {
            public var body: A { fatalError() }
        }

        public var variable: some Sequence<any Equatable> { [] }

        public func function<A: Protocols.ProtocolTest>() -> some Sequence<A> { [] }

        public func functionOptional<A: Protocols.ProtocolTest>() -> (some Sequence<A>)? { [] }

        public func functionTuple<A: Protocols.ProtocolTest>() -> (some Sequence<A>, A?) { ([], nil) }

        public func functionWhere<A: Protocols.ProtocolTest, B: Protocols.ProtocolTest>() -> (some Sequence<A>, (some Protocols.ProtocolTest<A>)?, some Collection<A>)? where A.Body == Generics.GenericRequirementTest<B>, A.Body.Body.Body == B { ([], AnyProtocolTest<A, B>(), []) }

        public func functionNested<A: Protocols.ProtocolTest & Equatable, B: Protocols.ProtocolTest & Equatable>(_: A, _: B) -> (some Sequence<[A]> & Equatable, (some Protocols.ProtocolTest<A>)?, some Collection<[A]> & Protocols.TestCollection<[A]> & Equatable)? where A.Body == Generics.GenericRequirementTest<B>, A.Body.Body.Body == B { ([], AnyProtocolTest<A, B>(), []) }

        /// Opaque-attribution proposal, name-fallback guard: `UnpinnedElementProtocol`
        /// declares an `Element` but the sugar pins only `TestCollection`'s —
        /// the anchor sits inside the composition, so the fallback must NOT
        /// fabricate `UnpinnedElementProtocol<[A]>`.
        public func functionNameFallbackGuard<A: Protocols.ProtocolTest>(_: A) -> some Protocols.TestCollection<[A]> & Protocols.UnpinnedElementProtocol & Equatable { NameFallbackGuardWitness<[A]>() }

        /// Opaque-attribution proposal, same-module refine closure: the constraint anchors
        /// on `ModuleBaseProtocol` (the declaring base, outside the
        /// composition) and attribution reaches `ModuleRefinedProtocol`
        /// through its own descriptor's requirement signature.
        public func functionModuleRefineClosure() -> some Protocols.ModuleRefinedProtocol<Int> & Equatable { ModuleRefineClosureWitness() }

        /// Opaque-attribution proposal, cross-image refine closure: the refine fact lives in
        /// SymbolTestsHelper. A `MachOFile` reader cannot reach it (bind
        /// symbol only — the parameter honestly degrades to none); a
        /// `MachOImage` reader resolves cross-image and attaches `<Int>`.
        public func functionCrossImageRefineClosure() -> some HelperRefinedProtocol<Int> & Equatable { CrossImageRefineClosureWitness() }
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
