/// What one instruction references.
public enum CodeReferenceTarget: Hashable, Sendable {
    /// A function: in the same image, in another, or wherever a stub, a GOT
    /// slot or a stub island led.
    case function(CodeLocation)
    /// A stub whose slot could not be followed; the name its indirect symbol
    /// carries.
    case importedSymbol(name: String)
    /// An Objective-C message send whose selector is known: through
    /// `objc_msgSend` or a selector stub, or a call to a libobjc entry point
    /// that stands for a send — `objc_alloc_init` for `[[Foo alloc] init]`,
    /// reported as two sends at its instruction, `alloc` and then `init`.
    case messageSend(selector: String, receiver: ReceiverClassHint)
    /// A send through `objc_msgSendSuper2` whose selector is known, and the
    /// class the lookup starts above: the one the sending method loads from
    /// `__objc_superrefs`, or the class its symbol names. `nil` for Swift
    /// code, which builds its `objc_super` from a class known only at run
    /// time.
    case superMessageSend(selector: String, className: String?)
    /// A Swift type, by where its context descriptor lies: a call to its
    /// metadata accessor, or the address of the accessor or of the type's
    /// metadata. A Swift class is also reached as an Objective-C class.
    case swiftType(descriptor: CodeLocation)
    /// Swift types named by a mangled name, which the scan does not take
    /// apart: see ``SwiftTypeName``.
    case swiftTypeName(SwiftTypeName)
    /// An Objective-C class reference: the class's runtime name (`NSWindow`,
    /// `_TtC7SwiftUI20FilePresenterWrapper`) and where the class object lies.
    /// A name alone can be ambiguous — a shared cache carries the macOS and the
    /// Mac Catalyst variant of a framework, and both define its classes. A
    /// reference to a metaclass is reported as one to its class.
    case objectiveCClass(name: String, location: CodeLocation)
    case indirect(IndirectCallEvidence)
    /// Code that lies in no image and in no recognized trampoline — or data
    /// in `__text` that decoded as a branch.
    case unrecognized(address: UInt64)
}

/// One instruction's reference.
public struct CodeReference: Hashable, Sendable {
    /// Whether the instruction calls, leaves the function, or only takes an
    /// address. Defined with the core of the analysis, which produces it.
    public typealias Kind = CodeReferenceKind

    /// The first instruction of the function the referencing instruction
    /// belongs to.
    public let function: CodeLocation
    /// The referencing instruction's unslid address, in the same image as
    /// ``function``.
    public let instructionAddress: UInt64
    public let kind: Kind
    public let target: CodeReferenceTarget
    /// A retain or release, an outlined value operation or another runtime
    /// helper; the target says which function.
    public let isRuntimeHelperCall: Bool

    public init(function: CodeLocation, instructionAddress: UInt64, kind: Kind, target: CodeReferenceTarget, isRuntimeHelperCall: Bool) {
        self.function = function
        self.instructionAddress = instructionAddress
        self.kind = kind
        self.target = target
        self.isRuntimeHelperCall = isRuntimeHelperCall
    }
}

/// A mangled name that names Swift types. Which types it names takes
/// demangling to tell, so a scan records where the name is and leaves that
/// to whoever asks (`CrossReferenceAnalyzer.swiftTypeKeys(in:)`).
public enum SwiftTypeName: Hashable, Sendable {
    /// The name a call to `__swift_instantiateConcreteTypeFromMangledName`
    /// (or the runtime's `swift_getTypeByMangledNameInContext`) instantiates:
    /// where its bytes start and how many there are. It may hold symbolic
    /// references to context descriptors.
    case mangledName(location: CodeLocation, length: Int)
    /// The symbol of a metadata accessor no type context descriptor stands
    /// for — a generic instance (`$sSNy10Foundation4DateVGMa`) or an
    /// existential — without the leading underscore.
    case accessorSymbol(String)
}
