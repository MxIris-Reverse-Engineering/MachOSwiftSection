import Semantic

extension MultilineTypeFormatting {
    /// How one line that runs past the width is laid out over several lines.
    ///
    /// `nil` when the line has nothing to break, and so stays as printed.
    struct LineLayout {
        init?(line: SourceLine, sourceComponents: [AtomicComponent], maximumLineWidth: Int) {
            return nil
        }

        func emit(into builder: inout FormattedComponentBuilder) {}
    }
}
