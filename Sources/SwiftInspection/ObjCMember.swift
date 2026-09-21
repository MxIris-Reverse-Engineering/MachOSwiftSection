import Foundation

/// One entry of a class's ObjC method table tied to the Swift member that
/// implements it (evolution proposals `objc-ancestor-override-recovery` and
/// `objc-member-selector-recovery`): the selector the member answers to,
/// whether it is a class method, which ancestor it overrides (if any), how
/// the Swift member was tied to the entry, and whether the selector is one
/// the source had to spell out in `@objc(name)`.
public struct ObjCMember: Sendable, Hashable {
    /// How the Swift member was tied to the ObjC method.
    public enum Evidence: Sendable, Hashable {
        /// The member's `To` thunk symbol sits at the method's IMP — the
        /// unstripped-binary case.
        case thunkSymbol
        /// The IMP carries no symbol (OS frameworks strip the thunks), but its
        /// code calls or materializes the member's own implementation symbol,
        /// and the member's name is the importer's spelling of the selector.
        case thunkReference
        /// Neither: the IMP's code references no Swift symbol (the body was
        /// inlined — a bare `super` call), and the member is the only one of
        /// the class whose name is the importer's spelling of the selector.
        /// Only produced when `ObjCMembers.infersOverridesFromSelectorNames` is on.
        case selectorName

        public var description: String {
            switch self {
            case .thunkSymbol: "To thunk symbol at the IMP"
            case .thunkReference: "the IMP's code references the implementation"
            case .selectorName: "selector name, no symbol evidence"
            }
        }
    }

    /// The class whose method table carries the entry, by its `class_ro_t`
    /// name (`NSGlassEffectView`, `_TtC7SwiftUI21CustomMarkedSliderCell`).
    /// For a category on a class another image defines, the target class.
    public let className: String
    public let selector: String
    public let isClassMethod: Bool
    /// The nearest ancestor also implementing the selector, by its
    /// `class_ro_t` name (`NSView`) — set when the member is an `override`
    /// of an ObjC-inherited member, `nil` otherwise.
    public let overriddenAncestorClassName: String?
    public let evidence: Evidence
    /// Whether the selector differs from the one the compiler derives from
    /// the member's Swift name, so the source spelled it in `@objc(name)`.
    /// Never set for an override (the selector is the overridden member's)
    /// nor for a witness of an `@objc` protocol requirement (the selector is
    /// the requirement's) — and therefore never set at all unless the whole
    /// ancestor chain and every adopted protocol could be read, since an
    /// unread one may be where the selector came from.
    public let hasExplicitSelector: Bool

    public init(className: String, selector: String, isClassMethod: Bool, overriddenAncestorClassName: String?, evidence: Evidence, hasExplicitSelector: Bool = false) {
        self.className = className
        self.selector = selector
        self.isClassMethod = isClassMethod
        self.overriddenAncestorClassName = overriddenAncestorClassName
        self.evidence = evidence
        self.hasExplicitSelector = hasExplicitSelector
    }

    public var isOverride: Bool { overriddenAncestorClassName != nil }

    /// The same fact with the explicit-selector flag cleared — for a property
    /// tied through its SETTER only, whose selector (`setName:`) is not what
    /// an `@objc(name)` on the property would spell.
    public func withoutExplicitSelector() -> ObjCMember {
        ObjCMember(className: className, selector: selector, isClassMethod: isClassMethod, overriddenAncestorClassName: overriddenAncestorClassName, evidence: evidence, hasExplicitSelector: false)
    }

    /// `-[NSGlassEffectView layout]` / `+[NSGlassEffectView defaultAnimationForKey:]`.
    public var description: String {
        "\(isClassMethod ? "+" : "-")[\(className) \(selector)]"
    }

    /// `-[NSView layout]` — the overridden method, for an override.
    public var overriddenMethodDescription: String? {
        guard let overriddenAncestorClassName else { return nil }
        return "\(isClassMethod ? "+" : "-")[\(overriddenAncestorClassName) \(selector)]"
    }
}

/// Every ObjC method of one class tied to a Swift member, keyed by the
/// Swift symbol that tied them: the member's `To` thunk (`$s…FTo`) when the
/// binary keeps it, otherwise the member's own implementation symbol the
/// stripped thunk's code was found to reference. A member definition looks
/// itself up by its own symbol name; both spellings are tried.
public struct ObjCMemberTable: Sendable {
    /// An ObjC method the join could tie to no Swift symbol: its IMP carries
    /// no symbol and its code references none of the class's members (the
    /// body was inlined). The name-based inference, when on, works from the
    /// overriding ones.
    public struct UnattributedMethod: Sendable, Hashable {
        public let selector: String
        public let isClassMethod: Bool
        public let overriddenAncestorClassName: String?

        public init(selector: String, isClassMethod: Bool, overriddenAncestorClassName: String?) {
            self.selector = selector
            self.isClassMethod = isClassMethod
            self.overriddenAncestorClassName = overriddenAncestorClassName
        }

        public var isOverride: Bool { overriddenAncestorClassName != nil }
    }

    /// The hierarchy the table was derived from; the ancestor chain is what
    /// the dump prints.
    public let hierarchy: ObjCClassHierarchy

    /// Symbol name → member fact.
    public let membersByImplementationSymbolName: [String: ObjCMember]

    public let unattributedMethods: [UnattributedMethod]

    public init(hierarchy: ObjCClassHierarchy, membersByImplementationSymbolName: [String: ObjCMember], unattributedMethods: [UnattributedMethod] = []) {
        self.hierarchy = hierarchy
        self.membersByImplementationSymbolName = membersByImplementationSymbolName
        self.unattributedMethods = unattributedMethods
    }

    public var isEmpty: Bool { membersByImplementationSymbolName.isEmpty && unattributedMethods.isEmpty }

    /// The override facts alone — the view the `override` recovery reads.
    public var overrides: [ObjCMember] {
        membersByImplementationSymbolName.values.filter(\.isOverride)
    }

    /// The overriding methods tied to no Swift symbol.
    public var unattributedOverriddenMethods: [UnattributedMethod] {
        unattributedMethods.filter(\.isOverride)
    }

    /// The fact for a member whose implementation symbol is `symbolName` (a
    /// function, an accessor): its ObjC entry point is the same name with
    /// `To` appended, and a stripped entry point is keyed by the
    /// implementation itself.
    public func member(forMemberSymbolNamed symbolName: String) -> ObjCMember? {
        membersByImplementationSymbolName[symbolName + "To"] ?? membersByImplementationSymbolName[symbolName]
    }

    /// The fact for an initializer, given its ALLOCATOR symbol (`…fC`): the
    /// ObjC `init…` method's IMP is the thunk of the INITIALIZER (`…fcTo`),
    /// and a stripped thunk calls the initializer (`…fc`), so the
    /// allocating-entry-point suffix is swapped for the initializing one
    /// before the lookup.
    public func member(forAllocatorSymbolNamed symbolName: String) -> ObjCMember? {
        guard symbolName.hasSuffix("fC") else { return nil }
        let initializerName = String(symbolName.dropLast(2)) + "fc"
        return membersByImplementationSymbolName[initializerName + "To"]
            ?? membersByImplementationSymbolName[initializerName]
            ?? membersByImplementationSymbolName[symbolName]
    }

    /// The name-based inference over the unattributed OVERRIDING methods:
    /// for each, the members (by caller-chosen key) whose shape is the
    /// importer's spelling of its selector; a method with exactly ONE such
    /// member is attributed to it. Two candidates attribute nothing — a name
    /// alone never picks. A key may carry several shapes (a property's
    /// getter and setter).
    public func inferredOverrides<Key: Hashable>(forMemberShapes shapes: [(key: Key, shape: ObjCMemberShape)]) -> [Key: ObjCMember] {
        var inferred: [Key: ObjCMember] = [:]
        for method in unattributedMethods where method.isOverride {
            var candidateKeys: [Key] = []
            for (key, shape) in shapes where shape.isConsistent(withSelector: method.selector, isClassMethod: method.isClassMethod) {
                if !candidateKeys.contains(key) {
                    candidateKeys.append(key)
                }
            }
            guard candidateKeys.count == 1, let key = candidateKeys.first else { continue }
            inferred[key] = ObjCMember(className: hierarchy.className, selector: method.selector, isClassMethod: method.isClassMethod, overriddenAncestorClassName: method.overriddenAncestorClassName, evidence: .selectorName)
        }
        return inferred
    }
}
