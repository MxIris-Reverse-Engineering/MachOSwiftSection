import Demangling

/// What the binary records about one class implemented through SE-0436's
/// `@objc @implementation extension` (evolution proposal
/// `objc-implementation-class-recognition`).
///
/// The compiler emits such a class as a PURE Objective-C class object: no
/// nominal type descriptor in `__swift5_types`, no field descriptor in
/// `__swift5_fieldmd`, and a class data pointer whose Swift bit is clear
/// (`ClassMetadataVisitor::layout()` takes its `isPureObjC()` branch, and
/// `getClassDataPointerHasSwiftMetadataBits()` asserts it never runs for one).
/// Everything Swift leaves behind is on the symbol side — the members mangle
/// as an extension of the `__C` class, every stored property gets a `Wvd`
/// field-offset global, and the implementing image EXPORTS the class's
/// metadata accessor `$sSo<Name>CMa` — while the ObjC side carries the ivar
/// list (with Swift-style type encodings: `?` for a type ObjC cannot
/// represent, an empty string for a stored property that is not `@objc`),
/// the method list (whose IMPs are the Swift `To` thunks) and the property
/// list. This value is the join of the two sides, computed once per image by
/// ``ObjCImplementationClassIndex``.
/// A final class rather than a struct on purpose: the declaration model holds
/// a reference to it on every `@objc @implementation` extension and to its
/// `InstanceVariable`s on every joined `VariableDefinition`, and those
/// definitions are copied around by value in the hundreds of thousands —
/// inlining the facts would have grown them past the instance-size ceilings
/// `DeclarationModelInstanceSizeTests` pins (proposal 0002). Immutable, so
/// reference semantics change nothing for a reader.
public final class ObjCImplementationClassFacts: Sendable {
    /// How the class was recognized. The tiers are ordered by strength: a
    /// symbol-level reason is definitive, the structural fallback is an
    /// inference and renders as such.
    public enum Evidence: Sendable, Hashable {
        public enum Reason: Sendable, Hashable {
            /// The image EXPORTS the class's Swift metadata accessor. Only the
            /// module implementing the class emits the public unique accessor
            /// (`MetadataAccessStrategy::PublicUniqueAccessor`); an imported
            /// ObjC class has `PublicNonUnique` linkage, so any image that
            /// needs its metadata emits a hidden non-unique accessor of its
            /// own — which a dyld cache's local symbol table still carries,
            /// and which therefore proves nothing.
            case metadataAccessorSymbol(name: String)
            /// `…vpWvd` field-offset globals for members of an extension of
            /// the class. A plain extension cannot add stored properties, so
            /// the symbol shape is only ever produced by an `@implementation`.
            case fieldOffsetSymbols(count: Int)
            /// Swift symbols found at the class's OWN method implementations
            /// (a category's implementations live in the category, never in
            /// the class's method list).
            case swiftSymbolsAtMethodImplementations(count: Int)
        }

        case definitive([Reason])
        /// No symbol-level evidence survived (a fully stripped image), but
        /// `swiftStyleEncodedInstanceVariableCount` of the class's ivars carry a
        /// type encoding only the Swift compiler writes (`?` or empty).
        case inferred(swiftStyleEncodedInstanceVariableCount: Int)

        public var isInferred: Bool {
            if case .inferred = self { return true }
            return false
        }

        /// A comment-ready description of the evidence.
        public var description: String {
            switch self {
            case .definitive(let reasons):
                return reasons.map(\.description).joined(separator: ", ")
            case .inferred(let count):
                return "inferred from ObjC class data: \(count) ivar\(count == 1 ? "" : "s") carr\(count == 1 ? "ies" : "y") Swift-style type encodings"
            }
        }
    }

    /// One entry of the class's ObjC ivar list, joined with its Swift
    /// field-offset symbol when the image still carries one.
    public final class InstanceVariable: Sendable {
        /// The ivar's name in the ObjC ivar list. Observed EMPTY for a
        /// header-declared property in an on-the-fly fixture, which is why the
        /// Swift join below keys on the offset variable, not the name.
        public let name: String
        public let offset: Int
        public let size: Int
        /// In bytes.
        public let alignment: Int
        /// The ObjC type encoding string, empty when the ivar carries none.
        public let typeEncoding: String
        /// The `…vpWvd` symbol whose global IS this ivar's offset variable, when
        /// the image still has the symbol.
        public let swiftFieldOffsetSymbolName: String?
        /// The Swift property name from that symbol.
        public let swiftPropertyName: String?
        /// The Swift type from that symbol (the `variable` node's type child).
        public let swiftTypeNode: NodeReference?

        public init(name: String, offset: Int, size: Int, alignment: Int, typeEncoding: String, swiftFieldOffsetSymbolName: String?, swiftPropertyName: String?, swiftTypeNode: NodeReference?) {
            self.name = name
            self.offset = offset
            self.size = size
            self.alignment = alignment
            self.typeEncoding = typeEncoding
            self.swiftFieldOffsetSymbolName = swiftFieldOffsetSymbolName
            self.swiftPropertyName = swiftPropertyName
            self.swiftTypeNode = swiftTypeNode
        }

        /// `?` or empty — encodings clang never writes for an ivar.
        public var hasSwiftStyleTypeEncoding: Bool {
            typeEncoding.isEmpty || typeEncoding == "?"
        }

        /// An empty encoding is what a stored property that is not `@objc`
        /// (a Swift-only member of the `@implementation`) gets.
        public var isObjCVisible: Bool {
            !typeEncoding.isEmpty
        }
    }

    /// One entry of a method list, with the Swift symbols found at its
    /// implementation (empty in a stripped image).
    public struct Method: Sendable {
        public let selector: String
        public let typeEncoding: String
        /// Reader-specific offset of the implementation, in the terms
        /// `MachORepresentableWithCache.addressString(forOffset:)` and
        /// `symbols(offset:)` take. `nil` when the entry carries no IMP.
        public let implementationOffset: Int?
        public let implementationSymbolNames: [String]
    }

    public struct Property: Sendable {
        public let name: String
        public let attributes: String
    }

    /// The bare ObjC class name (`NSGlassEffectView`).
    public let className: String
    public let superclassName: String?
    /// Offset of the class object in the image — the ordering key
    /// `swift-section dump --preferred-binary-order` sorts by.
    public let classObjectOffset: Int
    /// Raw `class_ro_t.flags`.
    public let readOnlyDataFlags: UInt32
    public let instanceStart: Int
    public let instanceSize: Int
    public let evidence: Evidence
    /// The Swift module that implements the class, read off the extension
    /// context of a field-offset symbol; `nil` when no such symbol survived.
    public let implementingModuleName: String?
    public let instanceVariables: [InstanceVariable]
    public let instanceMethods: [Method]
    public let classMethods: [Method]
    public let properties: [Property]
    public let protocolNames: [String]

    public init(className: String, superclassName: String?, classObjectOffset: Int, readOnlyDataFlags: UInt32, instanceStart: Int, instanceSize: Int, evidence: Evidence, implementingModuleName: String?, instanceVariables: [InstanceVariable], instanceMethods: [Method], classMethods: [Method], properties: [Property], protocolNames: [String]) {
        self.className = className
        self.superclassName = superclassName
        self.classObjectOffset = classObjectOffset
        self.readOnlyDataFlags = readOnlyDataFlags
        self.instanceStart = instanceStart
        self.instanceSize = instanceSize
        self.evidence = evidence
        self.implementingModuleName = implementingModuleName
        self.instanceVariables = instanceVariables
        self.instanceMethods = instanceMethods
        self.classMethods = classMethods
        self.properties = properties
        self.protocolNames = protocolNames
    }

    /// The ivar joined with the Swift property `name`, if any.
    public func instanceVariable(forSwiftPropertyNamed name: String) -> InstanceVariable? {
        instanceVariables.first { $0.swiftPropertyName == name }
    }
}

extension ObjCImplementationClassFacts.Evidence.Reason: CustomStringConvertible {
    public var description: String {
        switch self {
        case .metadataAccessorSymbol(let name):
            return "metadata accessor \(name)"
        case .fieldOffsetSymbols(let count):
            return "\(count) field-offset global\(count == 1 ? "" : "s")"
        case .swiftSymbolsAtMethodImplementations(let count):
            return "Swift symbols at \(count) method implementation\(count == 1 ? "" : "s")"
        }
    }
}
