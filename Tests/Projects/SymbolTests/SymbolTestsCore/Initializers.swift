import Foundation

public enum Initializers {
    public struct CustomInitializerError: Error {
        public let reason: String
        public init(reason: String) {
            self.reason = reason
        }
    }

    public class ConvenienceInitializerTest {
        public let primaryValue: Int
        public let secondaryValue: String

        public init(primaryValue: Int, secondaryValue: String) {
            self.primaryValue = primaryValue
            self.secondaryValue = secondaryValue
        }

        public convenience init(primaryValue: Int) {
            self.init(primaryValue: primaryValue, secondaryValue: "")
        }

        public convenience init() {
            self.init(primaryValue: 0, secondaryValue: "")
        }
    }

    public class RequiredInitializerTest {
        public let value: Int

        public required init(value: Int) {
            self.value = value
        }

        public required convenience init() {
            self.init(value: 0)
        }
    }

    public class RequiredInitializerSubclass: RequiredInitializerTest {
        public let extraValue: String

        public required init(value: Int) {
            self.extraValue = ""
            super.init(value: value)
        }

        public required convenience init() {
            self.init(value: 0)
        }
    }

    public struct FailableInitializerTest {
        public let value: Int

        public init?(value: Int) {
            guard value >= 0 else { return nil }
            self.value = value
        }

        public init!(unsafe value: Int) {
            self.value = value
        }
    }

    public struct TypedThrowingInitializerTest {
        public let value: Int

        public init(value: Int) throws(CustomInitializerError) {
            guard value >= 0 else {
                throw CustomInitializerError(reason: "negative")
            }
            self.value = value
        }
    }

    public actor AsyncInitializerActorTest {
        public let identifier: Int

        public init(identifier: Int) async {
            self.identifier = identifier
        }
    }
}
