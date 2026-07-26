import Foundation

/// A Swift-declared `@objc` protocol emits no Swift protocol descriptor and
/// contributes no witness table, so its existential stays a single word.
///
/// Declared at file scope on purpose: a nested `@objc` protocol's legacy
/// Objective-C name carries its parent context (`_TtPO<module><parent><name>_`),
/// which `ObjCProtocolIndex` does not parse — an independent gap from what this
/// fixture pins.
@objc public protocol WeakUnownedObjCDelegateTest {
    func handle()
}

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

    // MARK: - Reference storage over existentials

    /// A class-bound Swift protocol: an existential over it is a *two-word*
    /// value (object reference + witness table), so reference storage of it is
    /// 16 bytes rather than a single word.
    public protocol ReferenceDelegateTest: AnyObject {
        func notify()
    }

    /// A second class-bound protocol, for the composition case (three words).
    public protocol SecondaryDelegateTest: AnyObject {
        var isReady: Bool { get }
    }

    /// `weak` over a class-bound existential: 16 bytes (object word + one
    /// witness-table word). Modelling it as a single word — the regression
    /// this fixture pins — shifts every following field by 8.
    public struct WeakExistentialStructTest {
        public weak var delegate: (any ReferenceDelegateTest)?

        public init(delegate: (any ReferenceDelegateTest)?) {
            self.delegate = delegate
        }
    }

    /// `weak` over a two-protocol composition: 24 bytes (object word + two
    /// witness-table words).
    public struct WeakCompositionExistentialStructTest {
        public weak var delegate: (any ReferenceDelegateTest & SecondaryDelegateTest)?

        public init(delegate: (any ReferenceDelegateTest & SecondaryDelegateTest)?) {
            self.delegate = delegate
        }
    }

    /// `weak` over `AnyObject`: no witness table, so a single word — and the
    /// weak reference word's own zero extra inhabitants apply.
    public struct WeakAnyObjectStructTest {
        public weak var object: AnyObject?

        public init(object: AnyObject?) {
            self.object = object
        }
    }

    /// `weak` over an `@objc`-protocol existential: also a single word, since
    /// an ObjC protocol carries no Swift witness table — so the weak reference
    /// word's own zero extra inhabitants apply.
    public struct WeakObjCExistentialStructTest {
        public weak var delegate: (any WeakUnownedObjCDelegateTest)?

        public init(delegate: (any WeakUnownedObjCDelegateTest)?) {
            self.delegate = delegate
        }
    }

    /// `unowned` (safe) over an `@objc`-protocol existential: one word, one
    /// extra inhabitant — but *not* bitwise-takable, because an existential's
    /// refcounting is unknown even when its container is a single word.
    public struct UnownedObjCExistentialStructTest {
        public unowned var delegate: any WeakUnownedObjCDelegateTest

        public init(delegate: any WeakUnownedObjCDelegateTest) {
            self.delegate = delegate
        }
    }

    /// `unowned` (safe) over a class-bound existential: 16 bytes. The witness
    /// table word supplies the saturated extra inhabitants, so the container
    /// has more than the single one an unowned reference word alone would.
    public struct UnownedExistentialStructTest {
        public unowned var delegate: any ReferenceDelegateTest

        public init(delegate: any ReferenceDelegateTest) {
            self.delegate = delegate
        }
    }

    /// `unowned(unsafe)` over a class-bound existential: 16 bytes.
    public struct UnmanagedExistentialStructTest {
        public unowned(unsafe) var delegate: any ReferenceDelegateTest

        public init(delegate: any ReferenceDelegateTest) {
            self.delegate = delegate
        }
    }

    /// The class shape that regressed against SwiftUICore's `ViewResponder`: a
    /// `weak` existential followed by further stored properties. The trailing
    /// offsets only land correctly when the existential keeps both of its
    /// words, and — because this is a base class — a wrong width would shift
    /// every field of every subclass too.
    public class WeakExistentialHolderTest {
        public weak var delegate: (any ReferenceDelegateTest)?
        public weak var parent: ReferenceTargetTest?
        public var marker: Int = 0

        public init() {}
    }

    /// A subclass of the above, pinning that the base class's instance size is
    /// what the subclass's own fields start from.
    public class WeakExistentialSubclassTest: WeakExistentialHolderTest {
        public var trailing: Int = 0

        public override init() { super.init() }
    }
}
