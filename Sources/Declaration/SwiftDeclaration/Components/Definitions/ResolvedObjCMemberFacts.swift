import SwiftInspection

/// A member's ObjC-derived source facts, resolved against one consumer's
/// verdict on NAME-only evidence (evolution proposal
/// `objc-member-selector-recovery`).
///
/// The index records all three evidence tiers on `objcMember` and stops
/// there: the two joining tiers also write `@objc` into `attributes`, the
/// name-only one deliberately does not, because an attribute written at
/// index time reaches the `final` recovery and the export filter and cannot
/// be taken back. So the keywords a name-only tie implies — `@objc`,
/// `override`, `class`, and the `final` it must suppress, since a method the
/// ObjC runtime dispatches is `@objc dynamic` and never final — are derived
/// here, by whoever decides to act on the evidence.
///
/// `trustingSelectorNameEvidence: false` reproduces the definition's own
/// plain properties exactly; nothing else consults this type.
public struct ResolvedObjCMemberFacts: Sendable, Hashable {
    /// The ObjC method fact that counts under this verdict — `nil` when the
    /// only one recovered was name-only and the consumer does not act on it.
    public let objcMember: ObjCMember?
    /// The member's attributes, with `@objc` appended when a name-only tie
    /// is acted on (the joining tiers already wrote it at index time).
    public let attributes: [SwiftAttribute]
    public let isOverride: Bool
    public let isClassMember: Bool
    public let isFinal: Bool

    /// Whether `@objc` should print, whatever supplied it.
    public var isObjC: Bool { attributes.contains(.objc) }

    /// The selector to print inside `@objc(…)`, or `nil` when the compiler
    /// derives it from the Swift name.
    public var explicitSelector: String? {
        guard let objcMember, objcMember.hasExplicitSelector else { return nil }
        return objcMember.selector
    }

    /// The one place the verdict is applied. `isOverrideWithoutObjCMember` /
    /// `isClassMemberWithoutObjCMember` are what the member's vtable evidence
    /// alone says; `isClassMemberEligible` is the rest of the `class` keyword's
    /// precondition (a type-level member of the right kind), which an ObjC
    /// override satisfies the last part of — `override static` is not Swift.
    static func resolve(
        objcMember: ObjCMember?,
        trustingSelectorNameEvidence: Bool,
        declaredAttributes: [SwiftAttribute],
        isOverrideWithoutObjCMember: Bool,
        isClassMemberWithoutObjCMember: Bool,
        isClassMemberEligible: Bool,
        isFinal: Bool
    ) -> ResolvedObjCMemberFacts {
        // A name-only tie this consumer does not act on is dropped here and
        // nowhere else: the fact stays on the definition for whoever wants
        // it, and everything below reads as if the recovery had found nothing.
        let countedMember = objcMember.flatMap { member in
            member.isInferredFromSelectorName && !trustingSelectorNameEvidence ? nil : member
        }
        guard let countedMember else {
            return ResolvedObjCMemberFacts(
                objcMember: nil,
                attributes: declaredAttributes,
                isOverride: isOverrideWithoutObjCMember,
                isClassMember: isClassMemberWithoutObjCMember,
                isFinal: isFinal
            )
        }
        var attributes = declaredAttributes
        if !attributes.contains(.objc) {
            attributes.append(.objc)
        }
        return ResolvedObjCMemberFacts(
            objcMember: countedMember,
            attributes: attributes,
            isOverride: isOverrideWithoutObjCMember || countedMember.isOverride,
            isClassMember: isClassMemberWithoutObjCMember || (isClassMemberEligible && countedMember.isOverride),
            // Dispatched through the ObjC runtime, so overridable — whatever
            // the vtable's silence suggested.
            isFinal: false
        )
    }
}

extension FunctionDefinition {
    /// This member's source facts under `trustingSelectorNameEvidence` — see
    /// ``ResolvedObjCMemberFacts``.
    public func resolvedObjCMemberFacts(trustingSelectorNameEvidence: Bool) -> ResolvedObjCMemberFacts {
        .resolve(
            objcMember: objcMember,
            trustingSelectorNameEvidence: trustingSelectorNameEvidence,
            declaredAttributes: attributes,
            isOverrideWithoutObjCMember: (methodDescriptor?.isMethodOverride ?? false) || (methodDescriptor?.isMethodDefaultOverride ?? false),
            isClassMemberWithoutObjCMember: kind == .function && isGlobalOrStatic && methodDescriptor != nil,
            isClassMemberEligible: kind == .function && isGlobalOrStatic,
            isFinal: isFinal
        )
    }
}

extension VariableDefinition {
    /// This member's source facts under `trustingSelectorNameEvidence` — see
    /// ``ResolvedObjCMemberFacts``.
    public func resolvedObjCMemberFacts(trustingSelectorNameEvidence: Bool) -> ResolvedObjCMemberFacts {
        .resolve(
            objcMember: objcMember,
            trustingSelectorNameEvidence: trustingSelectorNameEvidence,
            declaredAttributes: attributes,
            isOverrideWithoutObjCMember: hasVTableOverrideAccessor,
            isClassMemberWithoutObjCMember: isGlobalOrStatic && hasVTableAccessor,
            isClassMemberEligible: isGlobalOrStatic,
            isFinal: isFinal
        )
    }
}

extension SubscriptDefinition {
    /// This member's source facts under `trustingSelectorNameEvidence` — see
    /// ``ResolvedObjCMemberFacts``.
    public func resolvedObjCMemberFacts(trustingSelectorNameEvidence: Bool) -> ResolvedObjCMemberFacts {
        .resolve(
            objcMember: objcMember,
            trustingSelectorNameEvidence: trustingSelectorNameEvidence,
            declaredAttributes: attributes,
            isOverrideWithoutObjCMember: hasVTableOverrideAccessor,
            isClassMemberWithoutObjCMember: isStatic && hasVTableAccessor,
            isClassMemberEligible: isStatic,
            isFinal: isFinal
        )
    }
}
