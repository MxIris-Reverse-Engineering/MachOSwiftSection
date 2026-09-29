import SwiftDiffing
import Semantic

/// One declaration's lifecycle across the evolution axis: its per-version
/// presence bitmap plus the `LineageEvent`s at the transitions where it
/// changed. This is pure data extracted from the `ABIEvolution` lineage — how
/// it becomes an on-screen comment (`// [●●○] removed in 26.0`) is the format
/// layer's job (`EvolutionMarking`), so a structured consumer can render it
/// however it likes.
public struct EvolutionAnnotation: Sendable, Equatable {
    /// Per-version existence, aligned with the evolution's version axis.
    public let presence: [Bool]
    /// The lifecycle events, ordered by `versionIndex`. Never empty: a
    /// declaration with no events carries no annotation at all (`nil` on its
    /// ``EvolutionLine``), which is what "present throughout and never
    /// changed" looks like.
    public let events: [LineageEvent]

    public init(presence: [Bool], events: [LineageEvent]) {
        self.presence = presence
        self.events = events
    }
}

/// One classified output line of an annotated evolution interface: the bare
/// single-line `content` (no structural indentation, no embedded newline, no
/// annotation text), the `indentLevel` a formatter multiplies by four spaces,
/// and the optional lifecycle `annotation` attached to this line.
///
/// `SwiftEvolutionInterfaceRenderer` produces a block-grouped
/// `[[EvolutionLine]]` stream — one inner array per top-level declaration
/// block — mirroring the two-sided renderer's `[[DiffLine]]`. `annotation` is
/// carried on the *last* line of the unit it describes (a member's declaration
/// line; a container header's `{` line); `nil` means the line belongs to a
/// declaration that is present on every version and never changed.
public struct EvolutionLine: Sendable {
    /// Exactly one visual line; `content.string` never contains a newline.
    public let content: SemanticString
    public let indentLevel: Int
    public let annotation: EvolutionAnnotation?

    public init(content: SemanticString, indentLevel: Int, annotation: EvolutionAnnotation?) {
        self.content = content
        self.indentLevel = indentLevel
        self.annotation = annotation
    }
}
