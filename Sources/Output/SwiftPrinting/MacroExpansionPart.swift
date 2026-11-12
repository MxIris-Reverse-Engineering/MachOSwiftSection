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
        /// Above the folded declaration of the tracked property named so —
        /// the region of kind `anchorKind` in a print with
        /// `marksAttachedMacros`: the attribute `@Observable` attaches to
        /// the property, `@Observation.ObservationTracked`, which the
        /// piece's nested expansion expands (evolution proposal
        /// `observable-nested-expansion`).
        case trackedPropertyAttribute(named: String)

        /// Below the folded declaration of the tracked property named so, in
        /// the expansion of its `@ObservationTracked`: the accessor block of
        /// the computed property the macro generated, the way the macro
        /// writes it whichever accessors the image keeps, then the storage.
        case trackedProperty(named: String)

        /// Above the closing brace of the type: the registrar and the
        /// methods the macro generated.
        case members

        /// Below the closing brace of the type: the conformance the macro
        /// generated.
        case conformance
    }

    /// A macro's attribute inside a piece, and the pieces that expand it —
    /// as Xcode expands a macro inside an expansion.
    public struct NestedExpansion: Sendable {
        /// Where the attribute is in the enclosing piece's content, in UTF-8
        /// code units of its `string`.
        public let attributeUTF8Range: Range<Int>

        /// The macro the attribute names.
        public let macro: SwiftAttachedMacro

        /// What the macro generates, placed relative to the same folded
        /// print as the enclosing piece.
        public let parts: [MacroExpansionPart]

        public init(attributeUTF8Range: Range<Int>, macro: SwiftAttachedMacro, parts: [MacroExpansionPart]) {
            self.attributeUTF8Range = attributeUTF8Range
            self.macro = macro
            self.parts = parts
        }
    }

    /// The macro that generated the piece.
    public let macro: SwiftAttachedMacro

    public let placement: Placement

    public let content: SemanticString

    /// The macros whose attributes `content` holds, with their expansions;
    /// empty for a piece that holds none.
    public let nestedExpansions: [NestedExpansion]

    /// The kind of the `AnnotationRegion` that marks where the piece goes in
    /// a print with `marksAttachedMacros`: the folded declaration of its
    /// tracked property, for the attribute and for what expanding it gives
    /// alike. `nil` for the pieces placed by the type's closing brace, which
    /// is the last line of the type's `DefinitionRegion` with
    /// `marksNestedDefinitions`, or of the print for the definition printed.
    public let anchorKind: AnnotationRegion.Kind?

    public init(macro: SwiftAttachedMacro, placement: Placement, content: SemanticString, nestedExpansions: [NestedExpansion] = [], anchorKind: AnnotationRegion.Kind? = nil) {
        self.macro = macro
        self.placement = placement
        self.content = content
        self.nestedExpansions = nestedExpansions
        self.anchorKind = anchorKind
    }
}
