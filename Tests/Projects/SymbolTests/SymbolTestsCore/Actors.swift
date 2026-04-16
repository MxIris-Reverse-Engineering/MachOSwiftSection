import Foundation

public enum Actors {
    public actor ActorTest {
        public var state: Int = 0

        public func mutateState() {
            state += 1
        }

        public func readState() -> Int {
            state
        }

        nonisolated public func nonisolatedMethod() -> String {
            "nonisolated"
        }
    }

    @globalActor
    public actor CustomGlobalActor {
        public static let shared = CustomGlobalActor()
    }

    @CustomGlobalActor
    public class GlobalActorAnnotatedClass {
        public var value: Int = 0

        public func method() -> Int { value }
    }

    @MainActor
    public class MainActorAnnotatedTest {
        public var value: Int = 0

        public func method() -> Int { value }

        nonisolated public func nonisolatedMethod() -> String { "" }
    }

    /// Fixture for conformance-level global actor isolation.
    ///
    /// `@<Actor> extension X: P { ... }` sets the
    /// `ProtocolConformanceFlags.hasGlobalActorIsolation` bit (bit 19) on the
    /// conformance descriptor and emits a trailing `TargetGlobalActorReference`
    /// pointing at the actor type. The SwiftInterface dumper recovers this and
    /// prints `extension X: @Actor P`. This is the only spelling of global-actor
    /// isolation that is recoverable from a release binary — method- and
    /// class-level `@MainActor` are not in the mangled name or any descriptor
    /// bit and are documented as ABI-limited in the roadmap.
    public protocol GlobalActorIsolatedProtocolTest {
        func isolatedRequirement()
    }

    public protocol CustomGlobalActorIsolatedProtocolTest {
        func customIsolatedRequirement()
    }

    public class GlobalActorIsolatedConformanceTest {
        public init() {}
    }
}

extension Actors.GlobalActorIsolatedConformanceTest: @MainActor Actors.GlobalActorIsolatedProtocolTest {
    @MainActor public func isolatedRequirement() {}
}

extension Actors.GlobalActorIsolatedConformanceTest: @Actors.CustomGlobalActor Actors.CustomGlobalActorIsolatedProtocolTest {
    @Actors.CustomGlobalActor public func customIsolatedRequirement() {}
}
