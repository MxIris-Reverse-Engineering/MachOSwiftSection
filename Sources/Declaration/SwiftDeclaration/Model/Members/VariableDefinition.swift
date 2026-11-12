import MemberwiseInit
import Demangling
import MachOSymbols
import MachOSwiftSection
import SwiftInspection
import SwiftObjCInterop

@MemberwiseInit(.public)
public struct VariableDefinition: Sendable, AccessorRepresentable {
    public let node: NodeReference
    public let name: String
    public let accessors: [Accessor]
    public let isGlobalOrStatic: Bool
    public var attributes: [SwiftAttribute] = []
    public var offset: Int? { accessors.first?.offset }
    public var hasVTableOffset: Bool { accessors.contains { $0.vtableOffset != nil } }

    /// A type-level variable whose accessors have vtable method descriptors was declared `class`:
    /// `static` members are implicitly final and never get one (mangling cannot tell them apart).
    /// An ObjC-side override is `class` as well — `override static` is not Swift.
    public var isClassMember: Bool { isGlobalOrStatic && (hasVTableAccessor || (objcMember?.isJoinedOverride ?? false)) }

    /// The ObjC method one of this property's accessors implements, set at
    /// index time from the class's ObjC method table. See `FunctionDefinition.objcMember`.
    public var objcMember: ObjCMember? = nil

    /// Recovered `final` (evolution proposal 0006): set at index time when the
    /// owning class's vtable was readable and none of this member's accessors
    /// carry a vtable method descriptor — the dispatch shape `final` compiles
    /// to. Always `false` outside class bodies (extensions, protocols, value
    /// types) and for type-level members (`static` is implicitly final).
    public var isFinal: Bool = false

    /// Set on conformance-extension members whose witness resolved through
    /// the protocol requirement's DEFAULT implementation (evolution proposal
    /// 0007) — the code lives in a protocol extension, not on the conforming
    /// type. See `FunctionDefinition.isProtocolExtensionDefault`.
    public var isProtocolExtensionDefault: Bool = false

    /// Set on a member of an `@objc @implementation` extension whose name
    /// matches a stored property the class's ObjC ivar list carries (evolution
    /// proposal `objc-implementation-class-recognition`): the accessor symbols
    /// this definition was built from belong to a STORED property, so the
    /// printer renders it as one — `var name: Type` with its field offset —
    /// instead of the `{ get set }` computed shape the symbols alone suggest.
    public var objcImplementationStorage: ObjCImplementationClassFacts.InstanceVariable? = nil

    /// The fields this property's SE-0400 init accessor initializes — what
    /// its `@storageRestrictions(initializes:)` lists — as far as the image
    /// tells (evolution proposal `init-accessor-recovery`). No image records
    /// the attribute, so it is inferred at index time from the type's stored
    /// properties (`InitAccessorFieldInference`): the field named `_<name>`
    /// with this property's type. `nil` when nothing tells, and for a
    /// property without an init accessor. `accesses:` is never recovered.
    public var initializedFieldNames: [String]? = nil
}
