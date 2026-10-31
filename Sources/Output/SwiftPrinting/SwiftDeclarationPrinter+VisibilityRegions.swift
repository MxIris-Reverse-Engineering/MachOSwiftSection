import SwiftDeclaration
import SwiftDeclarationRendering
import Semantic

// MARK: - Marking Optional Content

/// What `SwiftDeclarationPrintConfiguration.marksOptionalContent` changes in
/// the printer (evolution proposal `visibility-regions`): each piece of output
/// an option would decide is printed regardless and marked with a
/// `VisibilityRegion` conditioned on that option. The layout comments the
/// field renderers produce are marked the same way, through
/// `DeclarationRenderConfiguration.marksOptionalContent`.
extension SwiftDeclarationPrinter {
    /// `content` when `option` is on; when marking, always, in a region
    /// conditioned on `option`.
    @SemanticStringBuilder
    func optionalContent(_ option: SwiftVisibilityOption, @SemanticStringBuilder content: () -> SemanticString) -> SemanticString {
        if configuration.marksOptionalContent {
            VisibilityRegion(.enabled(option.rawValue), content: content())
        } else if configuration.isEnabled(option, resolvesOpaqueTypes: true) {
            content()
        }
    }

    /// A member declaration under the configured verdict on name-only ObjC
    /// evidence — or, when marking and the two verdicts give different
    /// facts, under each, conditioned on
    /// `.infersObjCOverridesFromSelectorNames` being on or off. Acting on the
    /// evidence does not only add `@objc` / `override` / `class`: it also
    /// takes `final` away, so neither verdict's declaration contains the
    /// other's.
    @SemanticStringBuilder
    func printUnderObjCVerdicts(
        of facts: (_ trustingSelectorNameEvidence: Bool) -> ResolvedObjCMemberFacts,
        @SemanticStringBuilder render: (ResolvedObjCMemberFacts) async throws -> SemanticString
    ) async rethrows -> SemanticString {
        let trustingFacts = facts(true)
        let distrustingFacts = facts(false)
        if configuration.marksOptionalContent, trustingFacts != distrustingFacts {
            try await VisibilityRegion(.enabled(SwiftVisibilityOption.infersObjCOverridesFromSelectorNames.rawValue)) {
                try await render(trustingFacts)
            }
            try await VisibilityRegion(.disabled(SwiftVisibilityOption.infersObjCOverridesFromSelectorNames.rawValue)) {
                try await render(distrustingFacts)
            }
        } else {
            try await render(trustsSelectorNameEvidence ? trustingFacts : distrustingFacts)
        }
    }

    /// Where content the exported-only filter rules on is printed, given one
    /// of the `isExcludedByExportFilter` predicates: everywhere when the
    /// filter keeps it; when the filter rules it out, nowhere (`nil`: leave
    /// it out) or, when marking, in a region visible only while
    /// `printExportedDeclarationsOnly` is off (evolution proposal
    /// `exported-only-marking-mode`).
    package func exportFilterVisibility(excluded isExcluded: Bool) -> VisibilityCondition? {
        guard isExcluded else { return .always }
        guard configuration.marksOptionalContent else { return nil }
        return .disabled(SwiftVisibilityOption.printExportedDeclarationsOnly.rawValue)
    }

    /// What a type's or an extension's body prints after its nested
    /// definitions, without its last line break when marking and the
    /// exported-only filter rules out every declaration in it
    /// (`excludesEveryDeclarationAfterNestedDefinitions(of:)`).
    ///
    /// That break is visible only while the filter is off, and a
    /// `DeclarationBlock` decides its own closing line break from the body as
    /// printed in full: projected with the filter on, a body left with only
    /// its nested definitions would end on their closing brace and close as
    /// `}}`. Without the break the block adds one of its own, visible
    /// whenever any of the body is, which stands in for it under every
    /// projection (evolution proposal `exported-only-marking-mode`).
    func bodyAfterNestedDefinitions(of definition: some Definition, @SemanticStringBuilder content: () async throws -> SemanticString) async rethrows -> SemanticString {
        let body = try await content()
        // A line break atom, not any atom reading "\n": marking comment
        // structure, the last piece of an enum case's layout block is one too
        // (evolution proposal `comment-structure`).
        guard configuration.marksOptionalContent,
              let lastAtom = body.components.last, lastAtom.string == "\n", lastAtom.type == .standard,
              excludesEveryDeclarationAfterNestedDefinitions(of: definition) else { return body }
        return body.dropLast()
    }

    /// The attributes a member's ObjC facts call for, each followed by a
    /// space.
    @SemanticStringBuilder
    func objcAttributes(_ objcFacts: ResolvedObjCMemberFacts) -> SemanticString {
        for attribute in objcFacts.attributes {
            Keyword(attribute.keyword)
            // An `@objc(name)` the source spelled out (evolution proposal
            // `objc-member-selector-recovery`): the selector the ObjC method
            // table carries is not the one the compiler derives from the name.
            if attribute == .objc, let explicitSelector = objcFacts.explicitSelector {
                Standard("(\(explicitSelector))")
            }
            Space()
        }
    }
}

extension SemanticString {
    /// This string with every atom visible only under `condition`, as
    /// wrapping it in a `VisibilityRegion` would make it — text and element
    /// boundaries untouched. Under `.always` it is returned as it is.
    package func visible(under condition: VisibilityCondition) -> SemanticString {
        var marked = self
        marked.markAtoms(from: 0, visibleUnder: condition)
        return marked
    }
}
