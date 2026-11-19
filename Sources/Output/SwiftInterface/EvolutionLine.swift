import SwiftDiffing
import Semantic

/// One declaration's lifecycle across the evolution axis: its per-version
/// presence bitmap plus the `LineageEvent`s at the transitions where it
/// changed. This is pure data extracted from the `ABIEvolution` lineage — how
/// it becomes an on-screen comment (`// [●●○] removed in 26.0`) is the format
/// layer's job (`EvolutionMarking`), so a structured consumer can render it
/// however it likes.
public struct EvolutionAnnotation: Sendable, Equatable {
    /// Per-version existence, aligned with the evolution's version axis —
    /// observed or inferred.
    public let presence: [Bool]
    /// The lifecycle events, ordered by `versionIndex`. Empty only when the
    /// annotation exists for versions that could not show the declaration
    /// (`presenceStates`); a declaration with no events and every version
    /// observed carries no annotation at all (`nil` on its ``EvolutionLine``),
    /// which is what "present throughout and never changed" looks like.
    public let events: [LineageEvent]
    /// What each version shows of the declaration, when some version could
    /// not show it — its image carries no local Swift symbols (evolution
    /// proposal `evolution-unobservable-presence`); `nil` when every version
    /// was observed.
    public let presenceStates: [LineagePresenceState]?
    /// Where the declaration moved between the images of a version's group
    /// (evolution proposal `image-group-evolution`); `nil` when it never did.
    public let imageMoves: [ImageMove]?

    public init(presence: [Bool], events: [LineageEvent], presenceStates: [LineagePresenceState]? = nil, imageMoves: [ImageMove]? = nil) {
        self.presence = presence
        self.events = events
        self.presenceStates = presenceStates
        self.imageMoves = imageMoves
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
