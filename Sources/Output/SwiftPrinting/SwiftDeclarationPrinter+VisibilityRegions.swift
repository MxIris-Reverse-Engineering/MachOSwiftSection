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
