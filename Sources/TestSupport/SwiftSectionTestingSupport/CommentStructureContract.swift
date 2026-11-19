import Semantic

/// The contract of a print marking comment structure (evolution proposal
/// `comment-structure`), checked against the same print with it off:
/// separated, the marked print is exactly the unmarked one — text, spans and
/// identifiers — and every comment in it lies in a region.
package enum CommentStructureContract {
    /// Why `marked` breaks the contract against `unmarked`; `nil` when it
    /// keeps it.
    package static func violation(marked: FrozenSemanticString, unmarked: FrozenSemanticString) -> String? {
        let (separatedText, annotations) = marked.separatingAnnotationRegions()
        if separatedText != unmarked {
            return "separated, the marked print differs from the unmarked one: \(firstDifference(between: separatedText, and: unmarked))"
        }
        if !unmarked.separatingAnnotationRegions().annotations.isEmpty {
            return "the unmarked print carries annotation regions"
        }
        let uncoveredComments = commentsOutsideEveryRegion(in: unmarked, annotations: annotations)
        if !uncoveredComments.isEmpty {
            return "comments in no region: \(uncoveredComments.prefix(5).map { "\"\($0)\"" }.joined(separator: ", "))"
        }
        return nil
    }

    /// The text of every `.comment` atom in `text` with a byte other than
    /// whitespace that no region of `annotations` covers. A region leaves out
    /// the whitespace at its ends, so a comment's own line break or leading
    /// indentation may lie outside one.
    package static func commentsOutsideEveryRegion(in text: FrozenSemanticString, annotations: AnnotationRegionTable) -> [String] {
        // The regions' union as disjoint ranges in text order, swept once
        // alongside the atoms, which come in text order too.
        var coveredRanges: [Range<Int>] = []
        for range in annotations.regions.map({ Int($0.utf8Offset) ..< Int($0.utf8Offset) + Int($0.utf8Length) }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = coveredRanges.last, range.lowerBound <= last.upperBound {
                coveredRanges[coveredRanges.count - 1] = last.lowerBound ..< max(last.upperBound, range.upperBound)
            } else {
                coveredRanges.append(range)
            }
        }
        var uncoveredComments: [String] = []
        var rangeIndex = 0
        var atomStart = 0
        for atom in text.components {
            let atomBytes = Array(atom.string.utf8)
            defer { atomStart += atomBytes.count }
            guard atom.type == .comment else { continue }
            for (byteIndex, byte) in atomBytes.enumerated() where !isWhitespace(byte) {
                let position = atomStart + byteIndex
                while rangeIndex < coveredRanges.count, coveredRanges[rangeIndex].upperBound <= position {
                    rangeIndex += 1
                }
                if rangeIndex == coveredRanges.count || !coveredRanges[rangeIndex].contains(position) {
                    uncoveredComments.append(atom.string)
                    break
                }
            }
        }
        return uncoveredComments
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
    }

    /// Where two frozen strings first differ, for a readable failure.
    package static func firstDifference(between left: FrozenSemanticString, and right: FrozenSemanticString) -> String {
        if left.string != right.string {
            let leftLines = left.string.split(separator: "\n", omittingEmptySubsequences: false)
            let rightLines = right.string.split(separator: "\n", omittingEmptySubsequences: false)
            let lineIndex = (0 ..< max(leftLines.count, rightLines.count)).first { index in
                index >= leftLines.count || index >= rightLines.count || leftLines[index] != rightLines[index]
            } ?? 0
            let leftLine = lineIndex < leftLines.count ? String(leftLines[lineIndex]) : "<none>"
            let rightLine = lineIndex < rightLines.count ? String(rightLines[lineIndex]) : "<none>"
            return "text differs at line \(lineIndex + 1):\n  marked: \(leftLine)\n  plain:  \(rightLine)"
        }
        let leftComponents = left.components
        let rightComponents = right.components
        let componentIndex = (0 ..< max(leftComponents.count, rightComponents.count)).first { index in
            index >= leftComponents.count || index >= rightComponents.count || leftComponents[index] != rightComponents[index]
        } ?? 0
        let leftComponent = componentIndex < leftComponents.count ? "\(leftComponents[componentIndex])" : "<none>"
        let rightComponent = componentIndex < rightComponents.count ? "\(rightComponents[componentIndex])" : "<none>"
        return "same text, span \(componentIndex) differs:\n  marked: \(leftComponent)\n  plain:  \(rightComponent)"
    }
}
