import MemberwiseInit
import Demangling
import MachOSwiftSection
import MachOFoundation
import Utilities
import SwiftInspection

@MemberwiseInit(.public)
public struct FunctionDefinition: Sendable {
    public let node: NodeReference
    public let name: String
    public let kind: FunctionKind
    public let symbol: DemangledSymbol
    public let isGlobalOrStatic: Bool
    public let methodDescriptor: MethodDescriptorWrapper?
    public let offset: Int?
    public let vtableOffset: Int?
    public var attributes: [SwiftAttribute] = []

    // `||`, not a `??` chain: `??` is right-associative, so
    // `a?.x ?? a?.y ?? false` parses as `a?.x ?? (a?.y ?? false)` — with a
    // non-nil descriptor the left side is always `.some(bool)` and the
    // default-override predicate is never consulted (the historical form
    // returned `false` for every `.methodDefaultOverride` wrapper).
    public var isOverride: Bool { objcAncestorOverride != nil || (methodDescriptor?.isMethodOverride ?? false) || (methodDescriptor?.isMethodDefaultOverride ?? false) }

    /// A type-level function with a vtable method descriptor was declared `class`:
    /// `static` members are implicitly final and never get one (mangling cannot tell them apart).
    /// An ObjC-side override is `class` as well — `override static` is not Swift.
    public var isClassMember: Bool { kind == .function && isGlobalOrStatic && (methodDescriptor != nil || objcAncestorOverride != nil) }

    /// Set at index time when this member's `To` thunk is the IMP of a
    /// selector an ObjC ancestor also implements (evolution proposal
    /// `objc-ancestor-override-recovery`): the `override` the Swift metadata
    /// cannot show, since overriding an ObjC-inherited member gets a NEW
    /// vtable entry rather than an override-table one — and an
    /// `@objc @implementation` class has no vtable at all. Feeds `isOverride`
    /// and `isClassMember`; the dump prints the selector and the ancestor.
    public var objcAncestorOverride: ObjCAncestorOverride? = nil

    /// Recovered `final` (evolution proposal 0006): set at index time when the
    /// owning class's vtable was readable and this member carries no vtable
    /// method descriptor — the dispatch shape `final` compiles to. Always
    /// `false` outside class bodies (extensions, protocols, value types), for
    /// type-level members (`static` is implicitly final), and for allocators
    /// (`final` is not a valid initializer modifier).
    public var isFinal: Bool = false

    /// Set on conformance-extension members whose witness resolved through
    /// the protocol requirement's DEFAULT implementation (evolution proposal
    /// 0007): the code lives in a protocol extension, not on the conforming
    /// type — several such witnesses typically share one identical-code-folded
    /// address, which is why they used to read as suspicious same-address
    /// "members" of the type (issue #106 §5).
    public var isProtocolExtensionDefault: Bool = false
}
