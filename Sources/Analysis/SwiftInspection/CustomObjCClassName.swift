/// The Objective-C runtime name a Swift class's source gave it (evolution
/// proposal `objc-custom-class-name`) — `@objc(NSColorModel)` on AppKit's
/// `NSColorModel`, which the ObjC runtime then knows by that name instead of
/// the `_TtC…` mangling it would otherwise carry.
///
/// Recovered from the class metadata, never from a symbol: the compiler sets
/// `ClassFlags::HasCustomObjCName` in the metadata's flag word and writes the
/// name into the class object's `class_ro_t`. That flag and that name are all
/// the binary keeps, so `@objc(Name)` and `@_objcRuntimeName(Name)` are told
/// apart by the class's object model instead — see ``Attribute``.
public struct CustomObjCClassName: Sendable, Hashable {
    /// Which source attribute the name is printed as.
    public enum Attribute: Sendable, Hashable {
        /// `@objc(Name)`: the class uses the Objective-C object model — it
        /// has an Objective-C ancestor — or is an `@objc` actor, which keeps
        /// Swift reference counting while inheriting `NSObject`.
        case objc
        /// `@_objcRuntimeName(Name)`: a class on the native Swift object model,
        /// renamed for the Objective-C runtime only. `@objc` is not legal on
        /// such a class (the standard library's `__EmptyArrayStorage` family).
        /// An `NSObject` subclass whose source wrote this attribute is
        /// indistinguishable from `@objc(Name)` and reads as ``objc``.
        case objcRuntimeName
    }

    /// The name as the Objective-C runtime knows the class — the class
    /// object's `class_ro_t` name. It may equal the Swift name
    /// (`@objc(NSScrollPocket) class NSScrollPocket`): without the attribute
    /// the runtime name would have been the mangling.
    public let name: String

    public let attribute: Attribute

    public init(name: String, attribute: Attribute) {
        self.name = name
        self.attribute = attribute
    }
}
