import Foundation

public enum VTableEntryVariants {
    public class VTableBaseTest {
        public func normalMethod() {}
        public func overridableMethod() -> Int { 0 }
        public final func finalMethod() {}
        public func asyncMethod() async -> Int { 0 }
        public func throwingMethod() throws -> Int { 0 }
        public func asyncThrowingMethod() async throws -> Int { 0 }

        public var normalProperty: Int {
            get { 0 }
            set {}
        }

        public var asyncProperty: Int {
            get async { 0 }
        }

        public var throwingProperty: Int {
            get throws { 0 }
        }

        public init() {}
    }

    public class VTableOverrideTest: VTableBaseTest {
        public override func overridableMethod() -> Int { 1 }
        public override func asyncMethod() async -> Int { 1 }
        public override func throwingMethod() throws -> Int { 1 }
    }

    public final class VTableFinalOverrideTest: VTableBaseTest {
        public override func overridableMethod() -> Int { 2 }
    }

    public class VTableDeepOverrideTest: VTableOverrideTest {
        public override func overridableMethod() -> Int { 3 }
        public override func asyncMethod() async -> Int { 3 }
    }

    /// Coverage matrix for `final` member recovery (evolution proposal 0006):
    /// every final/plain pairing across stored properties, lazy storage,
    /// computed properties, methods, and subscripts in one non-final class.
    /// The plain members put accessor entries in the vtable; the final ones
    /// keep their symbols but get no method descriptors.
    public class FinalMembersTest {
        public final var finalStoredProperty: Int = 0
        public var plainStoredProperty: Int = 0
        public let constantStoredProperty: Int = 0
        public final lazy var finalLazyProperty: String = "final"
        public lazy var plainLazyProperty: String = "plain"

        public final var finalComputedProperty: Int { 0 }
        public var plainComputedProperty: Int {
            get { 0 }
            set {}
        }

        public final func finalMethod() {}
        public func plainMethod() {}

        public final subscript(finalIndex index: Int) -> Int { 0 }
        public subscript(plainIndex index: Int) -> Int {
            get { 0 }
            set {}
        }

        public static func staticMethod() {}
        public class func classMethod() {}

        public init() {}
    }
}
