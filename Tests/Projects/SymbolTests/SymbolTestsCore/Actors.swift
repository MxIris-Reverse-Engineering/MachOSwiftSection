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
}
