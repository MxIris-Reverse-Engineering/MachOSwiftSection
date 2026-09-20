import Foundation

/// A member's `override` fact recovered from the ObjC side (evolution
/// proposal `objc-ancestor-override-recovery`): the selector the member's
/// ObjC entry point answers to, the nearest ancestor that also implements
/// it, and which kind of evidence tied the Swift member to that entry point.
public struct ObjCAncestorOverride: Sendable, Hashable {
    /// How the Swift member was tied to the overriding ObjC method.
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
        /// Only produced when `ObjCAncestorOverrides.infersOverridesFromSelectorNames` is on.
        case selectorName

        public var description: String {
            switch self {
            case .thunkSymbol: "To thunk symbol at the IMP"
            case .thunkReference: "the IMP's code references the implementation"
            case .selectorName: "selector name, no symbol evidence"
            }
        }
    }

    public let selector: String
    public let isClassMethod: Bool
    /// The nearest ancestor implementing the selector, by its `class_ro_t`
    /// name (`NSView`).
    public let ancestorClassName: String
    public let evidence: Evidence

    public init(selector: String, isClassMethod: Bool, ancestorClassName: String, evidence: Evidence) {
        self.selector = selector
        self.isClassMethod = isClassMethod
        self.ancestorClassName = ancestorClassName
        self.evidence = evidence
    }

    /// `-[NSView layout]` / `+[NSView defaultAnimationForKey:]`.
    public var description: String {
        "\(isClassMethod ? "+" : "-")[\(ancestorClassName) \(selector)]"
    }
}

/// Every override fact of one class, keyed by the Swift symbol that tied the
/// member to the overriding ObjC method: the member's `To` thunk (`$s…FTo`)
/// when the binary keeps it, otherwise the member's own implementation
/// symbol the stripped thunk's code was found to reference. A member
/// definition looks itself up by its own symbol name; both spellings are tried.
public struct ObjCAncestorOverrideTable: Sendable {
    /// An overriding ObjC method the join could tie to no Swift symbol: its
    /// IMP carries no symbol and its code references none of the class's
    /// members (the body was inlined). The name-based inference, when on,
    /// works from this list.
    public struct UnattributedMethod: Sendable, Hashable {
        public let selector: String
        public let isClassMethod: Bool
        public let ancestorClassName: String

        public init(selector: String, isClassMethod: Bool, ancestorClassName: String) {
            self.selector = selector
            self.isClassMethod = isClassMethod
            self.ancestorClassName = ancestorClassName
        }
    }

    /// The hierarchy the table was derived from; the ancestor chain is what
    /// the dump prints.
    public let hierarchy: ObjCClassHierarchy

    /// Symbol name → override fact.
    public let overridesByImplementationSymbolName: [String: ObjCAncestorOverride]

    public let unattributedOverriddenMethods: [UnattributedMethod]

    public init(hierarchy: ObjCClassHierarchy, overridesByImplementationSymbolName: [String: ObjCAncestorOverride], unattributedOverriddenMethods: [UnattributedMethod] = []) {
        self.hierarchy = hierarchy
        self.overridesByImplementationSymbolName = overridesByImplementationSymbolName
        self.unattributedOverriddenMethods = unattributedOverriddenMethods
    }

    public var isEmpty: Bool { overridesByImplementationSymbolName.isEmpty && unattributedOverriddenMethods.isEmpty }

    /// The override fact for a member whose implementation symbol is
    /// `symbolName` (a function, an accessor): its ObjC entry point is the
    /// same name with `To` appended, and a stripped entry point is keyed by
    /// the implementation itself.
    public func override(forMemberSymbolNamed symbolName: String) -> ObjCAncestorOverride? {
        overridesByImplementationSymbolName[symbolName + "To"] ?? overridesByImplementationSymbolName[symbolName]
    }

    /// The override fact for an initializer, given its ALLOCATOR symbol
    /// (`…fC`): the ObjC `init…` method's IMP is the thunk of the
    /// INITIALIZER (`…fcTo`), and a stripped thunk calls the initializer
    /// (`…fc`), so the allocating-entry-point suffix is swapped for the
    /// initializing one before the lookup.
    public func override(forAllocatorSymbolNamed symbolName: String) -> ObjCAncestorOverride? {
        guard symbolName.hasSuffix("fC") else { return nil }
        let initializerName = String(symbolName.dropLast(2)) + "fc"
        return overridesByImplementationSymbolName[initializerName + "To"]
            ?? overridesByImplementationSymbolName[initializerName]
            ?? overridesByImplementationSymbolName[symbolName]
    }

    /// The name-based inference over the unattributed methods: for each, the
    /// members (by caller-chosen key) whose shape is the importer's spelling
    /// of its selector; a method with exactly ONE such member is attributed
    /// to it. Two candidates attribute nothing — a name alone never picks.
    /// A key may carry several shapes (a property's getter and setter).
    public func inferredOverrides<Key: Hashable>(forMemberShapes shapes: [(key: Key, shape: ObjCMemberShape)]) -> [Key: ObjCAncestorOverride] {
        var inferred: [Key: ObjCAncestorOverride] = [:]
        for method in unattributedOverriddenMethods {
            var candidateKeys: [Key] = []
            for (key, shape) in shapes where shape.isConsistent(withSelector: method.selector, isClassMethod: method.isClassMethod) {
                if !candidateKeys.contains(key) {
                    candidateKeys.append(key)
                }
            }
            guard candidateKeys.count == 1, let key = candidateKeys.first else { continue }
            inferred[key] = ObjCAncestorOverride(selector: method.selector, isClassMethod: method.isClassMethod, ancestorClassName: method.ancestorClassName, evidence: .selectorName)
        }
        return inferred
    }
}
