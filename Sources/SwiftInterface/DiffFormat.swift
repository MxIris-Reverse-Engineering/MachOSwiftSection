import Foundation
import Semantic

/// A pluggable formatter for an annotated-interface diff.
///
/// ``SwiftDiffableInterfaceRenderer`` classifies the two indexed binaries into a
/// block-grouped stream of ``DiffLine``s — the outer array is the top-level
/// declaration blocks in render order, each inner array is that block's lines —
/// and hands the whole stream here. `DiffFormat` owns the one decision the
/// renderer deliberately does *not* make: how a ``DiffMarker`` becomes concrete
/// output. Because it receives the *entire* stream (not one line at a time), a
/// format can do document-level work such as computing unified-diff `@@` hunk
/// headers and line numbers.
///
/// Built-in presets: ``inline`` (the default git-diff `+`/`-`/` ` line prefixes),
/// ``markdownFenced`` (that same body inside a ```` ```diff ```` fence), and
/// ``unified(contextLines:oldLabel:newLabel:)`` (a real unified diff). To render
/// your own symbol with minimal boilerplate use ``perLine(blockSeparator:renderLine:)``.
public struct DiffFormat: Sendable {
    /// Given the renderer's block-grouped, single-line-split stream, produce the
    /// final `SemanticString` (no leading or trailing newline).
    public typealias Render = @Sendable (_ blocks: [[DiffLine]]) -> SemanticString

    public let render: Render

    public init(render: @escaping Render) {
        self.render = render
    }
}

extension DiffFormat {
    /// Builds a per-line format from a single closure, handling line splitting and
    /// joining for you. This is the minimal entry point for "render the diff
    /// symbol my own way": `renderLine` turns one classified line — its marker,
    /// bare content, and indent level — into its final `SemanticString` (without a
    /// trailing newline).
    ///
    /// Lines within a block are joined by a single newline; blocks that render to
    /// non-empty text are joined by `blockSeparator`. A block whose lines all
    /// render to nothing is skipped, mirroring the renderer's own empty-block
    /// filtering.
    public static func perLine(
        blockSeparator: SemanticString,
        renderLine: @escaping @Sendable (_ marker: DiffMarker, _ content: SemanticString, _ indentLevel: Int) -> SemanticString
    ) -> DiffFormat {
        DiffFormat { blocks in
            var result = SemanticString()
            var hasEmittedBlock = false
            for block in blocks {
                var blockOutput = SemanticString()
                var hasEmittedLine = false
                for line in block {
                    let renderedLine = renderLine(line.marker, line.content, line.indentLevel)
                    if renderedLine.string.isEmpty { continue }
                    if hasEmittedLine {
                        blockOutput.append("\n", type: .standard)
                    }
                    blockOutput.append(renderedLine)
                    hasEmittedLine = true
                }
                if blockOutput.string.isEmpty { continue }
                if hasEmittedBlock {
                    result.append(blockSeparator)
                }
                result.append(blockOutput)
                hasEmittedBlock = true
            }
            return result
        }
    }

    /// The default: git-diff-style line prefixes (`+` added, `-` removed, a space
    /// for unchanged) at column 0, then the structural indentation, then the
    /// content. Top-level blocks are separated by one bare blank line. This
    /// reproduces the original annotated-interface output byte-for-byte: its
    /// per-line rule is ``DiffMarking/inlineLineComponents``, shared with
    /// ``DiffMarking/markLines``.
    public static let inline: DiffFormat = .perLine(blockSeparator: "\n\n") { marker, content, indentLevel in
        SemanticString(components: DiffMarking.inlineLineComponents(marker: marker, content: content, indentLevel: indentLevel))
    }

    /// The ``inline`` body wrapped in a ```` ```diff ```` fenced code block, ready
    /// to paste into a pull request, issue, or Markdown document for GitHub-style
    /// diff highlighting. The fence length adapts to the longest backtick run in
    /// the body (CommonMark variable-length fences), so rendered content that
    /// itself contains backticks does not prematurely close the block. An empty
    /// diff produces empty output (no fence).
    public static let markdownFenced: DiffFormat = DiffFormat { blocks in
        let body = DiffFormat.inline.render(blocks)
        if body.string.isEmpty { return SemanticString() }

        var longestBacktickRun = 0
        var currentRun = 0
        for character in body.string {
            if character == "`" {
                currentRun += 1
                longestBacktickRun = max(longestBacktickRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        let fence = String(repeating: "`", count: max(3, longestBacktickRun + 1))

        var result = SemanticString(components: [AtomicComponent(string: fence + "diff\n", type: .standard)])
        result.append(body)
        result.append("\n" + fence, type: .standard)
        return result
    }

    /// A real unified diff (the format `git diff` / `diff -U` emit and `git apply`
    /// / `patch` consume): `--- old` / `+++ new` file headers, then one or more
    /// `@@ -oldStart,oldLength +newStart,newLength @@` hunks. Unchanged lines
    /// around each change are kept as context; runs more than `contextLines` apart
    /// are folded away.
    ///
    /// - Parameters:
    ///   - contextLines: Unchanged context lines to keep on each side of a change.
    ///     `nil` keeps everything (one hunk spanning the whole interface). Default 3.
    ///   - oldLabel: The label after `--- ` (typically the old binary's path).
    ///   - newLabel: The label after `+++ ` (typically the new binary's path).
    public static func unified(
        contextLines: Int? = 3,
        oldLabel: String = "old",
        newLabel: String = "new"
    ) -> DiffFormat {
        DiffFormat { blocks in
            UnifiedDiffFormatter(contextLines: contextLines, oldLabel: oldLabel, newLabel: newLabel).render(blocks)
        }
    }
}
