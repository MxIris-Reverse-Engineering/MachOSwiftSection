import Semantic
import SwiftDeclaration

/// One piece of what an attached macro generated in a type, for a host that
/// shows the expansion where Xcode's Expand Macro puts it rather than in one
/// block (evolution proposal `observable-macro-folding`):
/// `SwiftDeclarationPrinter.printMacroExpansionParts(of:attachedTo:)`.
///
/// The content has no indentation of its own and no line break around it:
/// a host indents it from the line it places it at.
public struct MacroExpansionPart: Sendable {
    /// Where the piece goes, relative to the folded print.
    public enum Placement: Hashable, Sendable {
        /// Below the folded declaration of the tracked property named so —
        /// the region of kind `anchorKind` in a print with
        /// `marksAttachedMacros`: the accessor block of the computed property
        /// the macro generated, when the image keeps its accessors, then its
        /// storage.
        case trackedProperty(named: String)

        /// Above the closing brace of the type: the registrar and the
        /// methods the macro generated.
        case members

        /// Below the closing brace of the type: the conformance the macro
        /// generated.
        case conformance
    }

    /// The macro that generated the piece.
    public let macro: SwiftAttachedMacro

    public let placement: Placement

    public let content: SemanticString

    public init(macro: SwiftAttachedMacro, placement: Placement, content: SemanticString) {
        self.macro = macro
        self.placement = placement
        self.content = content
    }

    /// The kind of the `AnnotationRegion` that marks where a
    /// `.trackedProperty` piece goes, in a print with `marksAttachedMacros`;
    /// `nil` for the pieces placed by the type's closing brace, which is the
    /// last line of the type's `DefinitionRegion` with `marksNestedDefinitions`,
    /// or of the print for the definition printed.
    public var anchorKind: AnnotationRegion.Kind? {
        guard case .trackedProperty(let propertyName) = placement else { return nil }
        return .attachedMacroTrackedProperty(macro, named: propertyName)
    }
}
