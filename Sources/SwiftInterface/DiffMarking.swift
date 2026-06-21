import Foundation
import Semantic

/// The git-diff-style marker classifying every rendered diff line.
public enum DiffMarker: String, Sendable, CaseIterable {
    case added = "+"
    case removed = "-"
    case unchanged = " "
}

/// One classified output line of an annotated-interface diff: a ``DiffMarker``,
/// the bare single-line `content` (no marker character, no structural
/// indentation, and no embedded newline), and the `indentLevel` a formatter
/// multiplies by four spaces and inserts *after* the marker.
///
/// ``SwiftDiffableInterfaceRenderer`` produces a block-grouped `[[DiffLine]]`
/// stream — one inner array per top-level declaration block — and hands it to a
/// ``DiffFormat``. That format is the single seam where a marker becomes a
/// concrete symbol, so a caller can render the diff however they like (git-diff
/// `+`/`-`, a unified-diff hunk, HTML, …) without the renderer baking any symbol
/// in.
public struct DiffLine: Sendable {
    public let marker: DiffMarker
    /// Exactly one visual line; `content.string` never contains a newline.
    public let content: SemanticString
    public let indentLevel: Int

    public init(marker: DiffMarker, content: SemanticString, indentLevel: Int) {
        self.marker = marker
        self.content = content
        self.indentLevel = indentLevel
    }
}

enum DiffMarking {
    /// Prefixes every line of `source` with `marker` at column 0, followed by the
    /// indentation for `indentLevel`, then the line's original content.
    ///
    /// `source` is one rendered unit (a type header, a single member, a closing
    /// brace) with NO indentation and NO leading/trailing newline of its own —
    /// the marker sits at column 0, git-diff style (`+    var x: Int`). Lines are
    /// joined by `\n`; the result has no trailing newline so callers can join
    /// units with `\n`.
    ///
    /// This is the eager, fully-marked form. It shares its per-line rule with
    /// ``inlineLineComponents`` — and therefore with ``DiffFormat/inline`` — so
    /// the structured (``markedLines``) and string (``markLines``) paths can never
    /// drift. Returns an empty `SemanticString` when `source` renders to nothing.
    static func markLines(_ source: SemanticString, marker: DiffMarker, indentLevel: Int) -> SemanticString {
        if source.string.isEmpty { return SemanticString() }

        let lines = splitIntoLines(source.components)
        var output: [AtomicComponent] = []
        output.reserveCapacity(lines.count * 3)
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                output.append(AtomicComponent(string: "\n", type: .standard))
            }
            output.append(contentsOf: inlineLineComponents(marker: marker, content: SemanticString(components: line), indentLevel: indentLevel))
        }
        return SemanticString(components: output)
    }

    /// Splits one rendered unit into per-line ``DiffLine``s, carrying the marker
    /// and indent level but NOT baking either into the text — that is the
    /// formatter's job.
    ///
    /// Empty `source` produces `[]` (matching ``markLines`` returning an empty
    /// `SemanticString`) so empty units never leave a stray marker. A blank
    /// interior line becomes a `DiffLine` whose content has no components.
    static func markedLines(_ source: SemanticString, marker: DiffMarker, indentLevel: Int) -> [DiffLine] {
        if source.string.isEmpty { return [] }
        return splitIntoLines(source.components).map { line in
            DiffLine(marker: marker, content: SemanticString(components: line), indentLevel: indentLevel)
        }
    }

    /// The atomic components of one git-diff-style line: the marker at column 0,
    /// then the indentation for `indentLevel` (only on non-blank lines, so blank
    /// lines carry no trailing whitespace after the marker), then the line's
    /// content components (their semantic types preserved untouched).
    ///
    /// A line counts as blank when every content component is all-whitespace —
    /// the same rule the original `markLines` used, NOT `content.string.isEmpty`,
    /// so a line of pure spaces is still treated as blank.
    static func inlineLineComponents(marker: DiffMarker, content: SemanticString, indentLevel: Int) -> [AtomicComponent] {
        let contentComponents = content.components
        let lineHasContent = contentComponents.contains { !$0.string.allSatisfy(\.isWhitespace) }
        let indentation = String(repeating: " ", count: max(0, indentLevel) * 4)
        var components: [AtomicComponent] = [AtomicComponent(string: marker.rawValue + (lineHasContent ? indentation : ""), type: .standard)]
        components.append(contentsOf: contentComponents)
        return components
    }

    /// Splits a flat atomic-component stream into per-line component arrays,
    /// breaking at every `\n` (which may appear mid-string within a component).
    /// Newline characters themselves are dropped — callers re-insert line breaks.
    private static func splitIntoLines(_ components: [AtomicComponent]) -> [[AtomicComponent]] {
        var lines: [[AtomicComponent]] = [[]]
        for component in components {
            let segments = component.string.components(separatedBy: "\n")
            for (segmentIndex, segment) in segments.enumerated() {
                if segmentIndex > 0 {
                    lines.append([])
                }
                if !segment.isEmpty {
                    lines[lines.count - 1].append(AtomicComponent(string: segment, type: component.type))
                }
            }
        }
        return lines
    }
}
