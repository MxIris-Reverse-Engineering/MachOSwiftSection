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
}
