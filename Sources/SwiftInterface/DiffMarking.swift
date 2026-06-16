import Foundation
import Semantic

/// The git-diff-style line marker prefixed to every rendered line.
enum DiffMarker: String {
    case added = "+"
    case removed = "-"
    case unchanged = " "
}

enum DiffMarking {
    /// Prefixes every line of `source` with `marker` at column 0, followed by
    /// the indentation for `indentLevel`, then the line's original content.
    ///
    /// `source` is one rendered unit (a type header, a single member, a closing
    /// brace) with NO indentation and NO leading/trailing newline of its own —
    /// the renderer adds indentation here so the marker can sit at column 0,
    /// git-diff style (`+    var x: Int`). Lines are joined by `\n`; the result
    /// has no trailing newline so callers can join units with `\n`.
    ///
    /// Returns an empty `SemanticString` when `source` renders to nothing (e.g. a
    /// member whose printer failed), so empty units never leave a stray marker.
    static func markLines(_ source: SemanticString, marker: DiffMarker, indentLevel: Int) -> SemanticString {
        if source.string.isEmpty { return SemanticString() }

        let indentation = String(repeating: " ", count: max(0, indentLevel) * 4)
        let lines = splitIntoLines(source.components)

        var output: [AtomicComponent] = []
        output.reserveCapacity(lines.count * 3)
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                output.append(AtomicComponent(string: "\n", type: .standard))
            }
            let lineHasContent = line.contains { !$0.string.allSatisfy(\.isWhitespace) }
            // Indent only non-blank lines so blank lines don't carry trailing
            // whitespace after the marker.
            output.append(AtomicComponent(string: marker.rawValue + (lineHasContent ? indentation : ""), type: .standard))
            output.append(contentsOf: line)
        }
        return SemanticString(components: output)
    }

    /// Splits a flat atomic-component stream into per-line component arrays,
    /// breaking at every `\n` (which may appear mid-string within a component).
    /// Newline characters themselves are dropped — the caller re-inserts line
    /// breaks while marking.
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
