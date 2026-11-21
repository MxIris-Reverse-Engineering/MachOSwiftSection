import Semantic

extension MultilineTypeFormatting {
    /// One line of the source: the fragments between two line breaks, and
    /// the line break ending it.
    struct SourceLine {
        /// The line's text, without its line break.
        let fragments: [SourceFragment]

        /// The `"\n"` ending the line; `nil` for the last line.
        let terminator: SourceFragment?

        /// How many spaces the line starts with.
        let leadingIndentation: Int

        /// The line's length in characters, less its leading indentation.
        let contentWidth: Int

        init(fragments: [SourceFragment], terminator: SourceFragment?) {
            self.fragments = fragments
            self.terminator = terminator
            var characterCount = 0
            var leadingSpaceCount = 0
            var isInLeadingIndentation = true
            for fragment in fragments {
                for character in fragment.text {
                    characterCount += 1
                    if isInLeadingIndentation {
                        if character == " " {
                            leadingSpaceCount += 1
                        } else {
                            isInLeadingIndentation = false
                        }
                    }
                }
            }
            self.leadingIndentation = leadingSpaceCount
            self.contentWidth = characterCount - leadingSpaceCount
        }

        /// The lines of `components`, split at every `"\n"` — including one
        /// inside a component, whose pieces each keep the component's index.
        static func lines(in components: [AtomicComponent]) -> [SourceLine] {
            var lines: [SourceLine] = []
            var currentFragments: [SourceFragment] = []
            for (componentIndex, component) in components.enumerated() {
                let string = component.string
                var segmentStart = string.startIndex
                while let lineBreakIndex = string[segmentStart...].firstIndex(of: "\n") {
                    if segmentStart < lineBreakIndex {
                        currentFragments.append(SourceFragment(componentIndex: componentIndex, text: string[segmentStart ..< lineBreakIndex]))
                    }
                    let afterLineBreak = string.index(after: lineBreakIndex)
                    let terminator = SourceFragment(componentIndex: componentIndex, text: string[lineBreakIndex ..< afterLineBreak])
                    lines.append(SourceLine(fragments: currentFragments, terminator: terminator))
                    currentFragments = []
                    segmentStart = afterLineBreak
                }
                if segmentStart < string.endIndex {
                    currentFragments.append(SourceFragment(componentIndex: componentIndex, text: string[segmentStart...]))
                }
            }
            lines.append(SourceLine(fragments: currentFragments, terminator: nil))
            return lines
        }
    }
}
