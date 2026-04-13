import Foundation

public enum WeakUnownedReferences {
    public class ReferenceTargetTest {
        public var value: Int = 0
        public init() {}
    }

    public class WeakReferenceHolderTest {
        public weak var weakReference: ReferenceTargetTest?
        public weak var weakAnyObject: AnyObject?
        public init() {}
    }

    public class UnownedReferenceHolderTest {
        public unowned var unownedReference: ReferenceTargetTest
        public unowned(safe) var unownedSafeReference: ReferenceTargetTest
        public unowned(unsafe) var unownedUnsafeReference: ReferenceTargetTest

        public init(target: ReferenceTargetTest) {
            self.unownedReference = target
            self.unownedSafeReference = target
            self.unownedUnsafeReference = target
        }
    }

    public class MixedReferenceHolderTest {
        public weak var weakReference: ReferenceTargetTest?
        public unowned var unownedReference: ReferenceTargetTest
        public var strongReference: ReferenceTargetTest

        public init(target: ReferenceTargetTest) {
            self.unownedReference = target
            self.strongReference = target
        }
    }
}
