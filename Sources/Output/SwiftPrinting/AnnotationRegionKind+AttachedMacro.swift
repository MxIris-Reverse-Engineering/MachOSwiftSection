import Semantic
import SwiftDeclaration

extension AnnotationRegion.Kind {
    /// The attribute of an attached macro the folded form prints —
    /// `@Observation.Observable` — marked when
    /// `SwiftDeclarationPrintConfiguration.marksAttachedMacros` is on
    /// (evolution proposal `observable-macro-folding`). One kind per macro
    /// (`attachedMacro.Observation.Observable`), so a host tells the macros
    /// apart without reading the attribute's text. Not a comment: a host
    /// drawing annotation regions as comments leaves these out.
    public static func attachedMacro(_ macro: SwiftAttachedMacro) -> Self {
        Self("attachedMacro.\(macro.moduleName).\(macro.name)")
    }

    /// The folded declaration of a property `macro` tracks — `var count:
    /// Swift.Int`, without the comments above it — marked when
    /// `SwiftDeclarationPrintConfiguration.marksAttachedMacros` is on. One
    /// kind per property, so a host places the expansion part of that
    /// property (`MacroExpansionPart.anchorKind`) below it by comparing kinds.
    public static func attachedMacroTrackedProperty(_ macro: SwiftAttachedMacro, named propertyName: String) -> Self {
        Self("attachedMacro.\(macro.moduleName).\(macro.name).trackedProperty.\(propertyName)")
    }
}
