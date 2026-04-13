import Foundation
import Distributed

public enum DistributedActors {
    public distributed actor DistributedActorTest {
        public typealias ActorSystem = LocalTestingDistributedActorSystem

        public distributed func remoteMethod(value: Int) -> Int {
            value * 2
        }

        public distributed func remoteThrowingMethod() throws -> String {
            "result"
        }

        public nonisolated var nonisolatedProperty: String {
            "nonisolated"
        }

        public distributed func parameterizedMethod(label: String, count: Int) -> String {
            String(repeating: label, count: count)
        }
    }

    public distributed actor GenericDistributedActorTest<Element: Codable & Sendable> {
        public typealias ActorSystem = LocalTestingDistributedActorSystem

        public distributed func process(element: Element) -> Element {
            element
        }
    }
}
