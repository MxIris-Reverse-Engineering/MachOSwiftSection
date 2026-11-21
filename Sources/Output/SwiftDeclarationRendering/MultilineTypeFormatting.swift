import Semantic

/// Lays the long types of printed Swift source out over several lines.
///
/// A type that runs past `maximumLineWidth` is broken at its brackets: every
/// generic argument list with two or more arguments puts each argument on a
/// line of its own, and a single-argument generic list, a tuple, a parameter
/// list or collection sugar breaks only when one of its elements spans
/// several lines. A type that fits, and every line that fits, stays as
/// printed. Only a generic argument list running past the width starts a
/// break: a line that is long for any other reason — many short parameters,
/// a trailing comment — is left alone.
///
/// ```swift
/// let formatting = MultilineTypeFormatting(maximumLineWidth: 100)
/// let interface = formatting.format(try await printer.printTypeDefinition(definition))
/// ```
///
/// Formatting only adds line breaks and indentation, and drops the space of
/// each `, ` between broken elements. Everything else — the text, every
/// component's semantic type and identifier, and so every visibility,
/// definition and annotation region — stays as it was. Format a finished
/// print, not a piece still being composed into a container: when a line
/// changes, the result keeps one element per component rather than the
/// source's element boundaries. When no line changes, the result is `source`
/// itself.
///
/// The width does not count a line's own indentation, so a declaration
/// breaks the same way at any nesting depth: a nested definition taken out
/// of its formatted parent and stripped of its indentation reads exactly as
/// the definition printed on its own and then formatted.
public struct MultilineTypeFormatting: Hashable, Sendable {
    /// The widest a line's content may be, in characters, not counting the
    /// line's own indentation.
    public var maximumLineWidth: Int

    /// - Precondition: `maximumLineWidth > 0`.
    public init(maximumLineWidth: Int = 100) {
        precondition(maximumLineWidth > 0, "MultilineTypeFormatting needs a positive maximum line width, got \(maximumLineWidth)")
        self.maximumLineWidth = maximumLineWidth
    }

    /// `source` with its long types laid out over several lines.
    ///
    /// - Precondition: `maximumLineWidth > 0`.
    public func format(_ source: SemanticString) -> SemanticString {
        precondition(maximumLineWidth > 0, "MultilineTypeFormatting needs a positive maximum line width, got \(maximumLineWidth)")
        let sourceComponents = source.components
        var builder = FormattedComponentBuilder(sourceComponents: sourceComponents)
        var hasChangedLine = false
        for line in SourceLine.lines(in: sourceComponents) {
            if line.contentWidth > maximumLineWidth, let layout = LineLayout(line: line, sourceComponents: sourceComponents, maximumLineWidth: maximumLineWidth) {
                layout.emit(into: &builder)
                hasChangedLine = true
            } else {
                builder.append(contentsOf: line.fragments)
            }
            if let terminator = line.terminator {
                builder.append(terminator)
            }
        }
        guard hasChangedLine else { return source }
        return SemanticString(components: builder.finish())
    }
}

// MARK: - Fragments

extension MultilineTypeFormatting {
    /// A run of one source component's text.
    ///
    /// Fragments are how a line is taken apart without losing where its text
    /// came from: every piece of output that is not an inserted line break or
    /// indentation is a fragment, and adjacent fragments of one component
    /// join back into that component on output.
    struct SourceFragment {
        let componentIndex: Int
        let text: Substring
    }

    /// Collects the output components, joining adjacent fragments of one
    /// source component back into a single component, so an unchanged run
    /// of the source comes out component for component as it went in.
    struct FormattedComponentBuilder {
        let sourceComponents: [AtomicComponent]

        private var components: [AtomicComponent] = []

        private var pendingFragment: SourceFragment?

        init(sourceComponents: [AtomicComponent]) {
            self.sourceComponents = sourceComponents
        }

        mutating func append(_ fragment: SourceFragment) {
            guard !fragment.text.isEmpty else { return }
            if let pendingFragment,
               pendingFragment.componentIndex == fragment.componentIndex,
               pendingFragment.text.endIndex == fragment.text.startIndex {
                let joinedText = pendingFragment.text.base[pendingFragment.text.startIndex ..< fragment.text.endIndex]
                self.pendingFragment = SourceFragment(componentIndex: fragment.componentIndex, text: joinedText)
                return
            }
            flushPendingFragment()
            pendingFragment = fragment
        }

        mutating func append(contentsOf fragments: [SourceFragment]) {
            for fragment in fragments {
                append(fragment)
            }
        }

        /// A line break and the indentation after it, both carrying
        /// `identifier` so they sit in the same regions as the component
        /// they were inserted next to.
        mutating func appendLineBreak(indentation: Int, identifier: String?) {
            flushPendingFragment()
            components.append(AtomicComponent(string: "\n", type: .standard, identifier: identifier))
            if indentation > 0 {
                components.append(AtomicComponent(string: String(repeating: " ", count: indentation), type: .standard, identifier: identifier))
            }
        }

        mutating func finish() -> [AtomicComponent] {
            flushPendingFragment()
            return components
        }

        private mutating func flushPendingFragment() {
            guard let pendingFragment else { return }
            let sourceComponent = sourceComponents[pendingFragment.componentIndex]
            if pendingFragment.text.startIndex == pendingFragment.text.base.startIndex,
               pendingFragment.text.endIndex == pendingFragment.text.base.endIndex {
                components.append(sourceComponent)
            } else {
                components.append(AtomicComponent(string: String(pendingFragment.text), type: sourceComponent.type, identifier: sourceComponent.identifier))
            }
            self.pendingFragment = nil
        }
    }
}
