import Foundation

public enum DefaultArguments {
    public struct DefaultArgumentMethodTest {
        public func greet(name: String = "World", repeated: Int = 1, punctuation: Character = "!") -> String {
            String(repeating: "\(name)\(punctuation) ", count: repeated)
        }

        public func append(_ value: Int, to collection: [Int] = []) -> [Int] {
            collection + [value]
        }

        public static func createDefault(label: String = "default", value: Int = 0) -> DefaultArgumentMethodTest {
            DefaultArgumentMethodTest()
        }
    }

    public struct DefaultArgumentInitializerTest {
        public var name: String
        public var count: Int
        public var enabled: Bool

        public init(name: String = "default", count: Int = 0, enabled: Bool = true) {
            self.name = name
            self.count = count
            self.enabled = enabled
        }
    }

    public struct DefaultArgumentSubscriptTest {
        public subscript(index: Int = 0, fallback fallback: String = "") -> String {
            fallback
        }
    }

    public class DefaultArgumentClassTest {
        public func process(value: Int = 42, multiplier: Double = 1.0) -> Double {
            Double(value) * multiplier
        }

        public init(initial: Int = 0, scale: Double = 1.0) {}
    }
}
