import Foundation

public enum Availability {
    @available(macOS 12.0, iOS 15.0, *)
    public struct MultiPlatformAvailableTest {
        public var value: Int
        public init(value: Int) {
            self.value = value
        }
    }

    @available(macOS, deprecated: 13.0, message: "Use RenamedAvailabilityNewTest instead")
    public struct DeprecatedAvailabilityTest {
        public var value: Int
        public init(value: Int) {
            self.value = value
        }
    }

    public struct RenamedAvailabilityNewTest {
        public init() {}
    }

    @available(macOS, introduced: 10.15, deprecated: 14.0, obsoleted: 15.0, message: "Obsoleted in macOS 15")
    public struct ObsoletedAvailabilityTest {
        public init() {}
    }

    public struct AvailabilityMemberTest {
        @available(macOS 13.0, *)
        public var modernField: Int {
            0
        }

        @available(macOS, deprecated: 13.0)
        public func deprecatedMethod() {}

        @available(*, unavailable, message: "No longer supported")
        public func unavailableMethod() {}

        public init() {}
    }
}
