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

    /// Weak storage in a *struct* (the classes above are references, so the
    /// whole-type suite never sees their instance layout): zero extra
    /// inhabitants and not bitwise-takable.
    public struct WeakReferenceStructTest {
        public weak var object: ReferenceTargetTest?

        public init(object: ReferenceTargetTest?) {
            self.object = object
        }
    }

    /// Unowned (safe) storage in a struct: exactly one extra inhabitant
    /// (the ObjC-interop-conservative IRGen lowering), not the underlying
    /// reference's saturated count.
    public struct UnownedReferenceStructTest {
        public unowned var object: ReferenceTargetTest

        public init(object: ReferenceTargetTest) {
            self.object = object
        }
    }

    /// Two empty cases over a weak payload (zero extra inhabitants): both
    /// spill, so the enum takes a tag byte — size 9, stride 16.
    public enum EnumOverWeakReferenceStructTest {
        case payload(WeakReferenceStructTest)
        case first
        case second
    }

    /// Two empty cases over an unowned payload (one extra inhabitant): one
    /// fits, one spills — size 9, stride 16. If unowned wrongly inherited the
    /// reference's saturated count, this enum would mis-size to 8.
    public enum EnumOverUnownedReferenceStructTest {
        case payload(UnownedReferenceStructTest)
        case first
        case second
    }
}
