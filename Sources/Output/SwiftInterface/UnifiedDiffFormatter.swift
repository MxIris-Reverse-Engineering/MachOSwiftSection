import Foundation
import Semantic

/// Turns the renderer's block-grouped ``DiffLine`` stream into a real unified
/// diff. Backs ``DiffFormat/unified(contextLines:oldLabel:newLabel:)``.
///
/// The line-number model is the standard one: an unchanged line advances both
/// the old and new counters, a removed line advances only the old counter, an
/// added line advances only the new counter. Changes are grouped into hunks
/// whose context windows (`contextLines` on each side) are merged when they touch
/// or overlap, matching `diff -U`.
struct UnifiedDiffFormatter {
    let contextLines: Int?
    let oldLabel: String
    let newLabel: String

    /// One flattened line with its assigned 1-based old/new line numbers (`nil`
    /// on the side where the line does not exist).
    private struct NumberedLine {
        let line: DiffLine
        let oldNumber: Int?
        let newNumber: Int?
    }

    func render(_ blocks: [[DiffLine]]) -> SemanticString {
        let flattened = flatten(blocks)
        if flattened.isEmpty { return SemanticString() }

        let numbered = number(flattened)
        let hunks = groupIntoHunks(numbered)
        if hunks.isEmpty { return SemanticString() }

        var lines: [SemanticString] = []
        lines.append(SemanticString(components: [AtomicComponent(string: "--- " + oldLabel, type: .standard)]))
        lines.append(SemanticString(components: [AtomicComponent(string: "+++ " + newLabel, type: .standard)]))
        for hunk in hunks {
            lines.append(headerLine(for: hunk, in: numbered))
            for index in hunk.start ... hunk.end {
                let line = numbered[index].line
                lines.append(SemanticString(components: DiffMarking.inlineLineComponents(marker: line.marker, content: line.content, indentLevel: line.indentLevel)))
            }
        }
        return join(lines)
    }

    // MARK: - Step 0: flatten

    /// Flattens the blocks into one line stream, mirroring the inline formatter's
    /// bare `"\n\n"` block separator as a single unchanged blank context line so
    /// the diff stays visually block-separated and the line numbers line up with
    /// what a reader sees. Empty blocks are skipped, matching `perLine`.
    private func flatten(_ blocks: [[DiffLine]]) -> [DiffLine] {
        var flattened: [DiffLine] = []
        var hasEmittedBlock = false
        for block in blocks where !block.isEmpty {
            if hasEmittedBlock {
                flattened.append(DiffLine(marker: .unchanged, content: SemanticString(), indentLevel: 0))
            }
            flattened.append(contentsOf: block)
            hasEmittedBlock = true
        }
        return flattened
    }

    // MARK: - Step 1: line numbering

    private func number(_ flattened: [DiffLine]) -> [NumberedLine] {
        var numbered: [NumberedLine] = []
        numbered.reserveCapacity(flattened.count)
        var oldLineNumber = 0
        var newLineNumber = 0
        for line in flattened {
            switch line.marker {
            case .unchanged:
                oldLineNumber += 1
                newLineNumber += 1
                numbered.append(NumberedLine(line: line, oldNumber: oldLineNumber, newNumber: newLineNumber))
            case .removed:
                oldLineNumber += 1
                numbered.append(NumberedLine(line: line, oldNumber: oldLineNumber, newNumber: nil))
            case .added:
                newLineNumber += 1
                numbered.append(NumberedLine(line: line, oldNumber: nil, newNumber: newLineNumber))
            }
        }
        return numbered
    }

    // MARK: - Step 2 & 3: group changes into hunks

    private struct Hunk {
        var start: Int
        var end: Int
    }

    private func groupIntoHunks(_ numbered: [NumberedLine]) -> [Hunk] {
        let count = numbered.count
        // `nil` context means "keep the whole interface": a window of `count`
        // around any change reaches every line, so all runs merge into one hunk.
        let context = contextLines ?? count

        // Maximal runs of consecutive change lines.
        var runs: [(start: Int, end: Int)] = []
        var runStart: Int?
        for index in 0 ..< count {
            let isChange = numbered[index].line.marker != .unchanged
            if isChange {
                if runStart == nil { runStart = index }
            } else if let start = runStart {
                runs.append((start, index - 1))
                runStart = nil
            }
        }
        if let start = runStart {
            runs.append((start, count - 1))
        }
        if runs.isEmpty { return [] }

        // Expand each run by the context window, merging when windows touch.
        var hunks: [Hunk] = []
        for run in runs {
            let expandedStart = max(0, run.start - context)
            let expandedEnd = min(count - 1, run.end + context)
            if !hunks.isEmpty, expandedStart <= hunks[hunks.count - 1].end + 1 {
                hunks[hunks.count - 1].end = max(hunks[hunks.count - 1].end, expandedEnd)
            } else {
                hunks.append(Hunk(start: expandedStart, end: expandedEnd))
            }
        }
        return hunks
    }

    // MARK: - Step 4: hunk header

    private func headerLine(for hunk: Hunk, in numbered: [NumberedLine]) -> SemanticString {
        let slice = numbered[hunk.start ... hunk.end]
        let oldNumbers = slice.compactMap(\.oldNumber)
        let newNumbers = slice.compactMap(\.newNumber)

        // A side's start is the first real line number in the hunk; for a hunk
        // with no line on that side (a pure insertion/deletion with no context on
        // that side) GNU diff uses the preceding line number, or 0 at the file
        // start.
        let oldStart = oldNumbers.first ?? precedingNumber(before: hunk.start, in: numbered, on: \.oldNumber) ?? 0
        let newStart = newNumbers.first ?? precedingNumber(before: hunk.start, in: numbered, on: \.newNumber) ?? 0

        let header = "@@ -" + range(start: oldStart, length: oldNumbers.count) + " +" + range(start: newStart, length: newNumbers.count) + " @@"
        return SemanticString(components: [AtomicComponent(string: header, type: .standard)])
    }

    private func precedingNumber(before index: Int, in numbered: [NumberedLine], on keyPath: KeyPath<NumberedLine, Int?>) -> Int? {
        var cursor = index - 1
        while cursor >= 0 {
            if let number = numbered[cursor][keyPath: keyPath] {
                return number
            }
            cursor -= 1
        }
        return nil
    }

    /// Formats one side of a hunk header. GNU diff omits the `,length` when the
    /// length is exactly 1.
    private func range(start: Int, length: Int) -> String {
        length == 1 ? "\(start)" : "\(start),\(length)"
    }

    // MARK: - Assembly

    private func join(_ lines: [SemanticString]) -> SemanticString {
        var result = SemanticString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append("\n", type: .standard)
            }
            result.append(line)
        }
        return result
    }
}
