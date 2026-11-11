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
}
