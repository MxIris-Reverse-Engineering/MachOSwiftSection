import Semantic

/// Assembles a container declaration (struct / class / enum / protocol /
/// extension) into ONE flat line list from its header(s), the marker for the
/// container as a whole, and its already-classified body units.
///
/// Within-container seams (header ↔ body ↔ closing brace, and between body units)
/// are single newlines, so they all live in one inner array; only the top-level
/// block boundary carries the ``DiffFormat``'s block separator.
///
/// For an added/removed container every line carries the container marker. For a
/// common container the header is unchanged unless it actually changed (e.g. a
/// conformance or generic-signature edit), in which case the old header is shown
/// as `-` and the new header as `+`; the body carries its own per-member markers.
/// An empty body renders inline as ` {}` with no closing-brace line.
///
/// This is a pure function of its inputs — it touches no renderer state — so it
/// lives here, apart from the generic renderer, where it can be unit-tested
/// directly against synthetic headers and body units.
enum DiffContainerAssembler {
    static func assemble(oldHeader: SemanticString, newHeader: SemanticString, marker: DiffMarker, bodyUnits: [[DiffLine]], level: Int) -> [DiffLine] {
        let hasBody = !bodyUnits.isEmpty
        let opening = hasBody ? " {" : " {}"
        let headerLevel = level - 1

        var lines: [DiffLine] = []
        switch marker {
        case .added:
            lines += DiffMarking.markedLines(newHeader.appending(opening), marker: .added, indentLevel: headerLevel)
        case .removed:
            lines += DiffMarking.markedLines(oldHeader.appending(opening), marker: .removed, indentLevel: headerLevel)
        case .unchanged:
            if oldHeader.string != newHeader.string {
                lines += DiffMarking.markedLines(oldHeader.appending(opening), marker: .removed, indentLevel: headerLevel)
                lines += DiffMarking.markedLines(newHeader.appending(opening), marker: .added, indentLevel: headerLevel)
            } else {
                lines += DiffMarking.markedLines(newHeader.appending(opening), marker: .unchanged, indentLevel: headerLevel)
            }
        }

        for unit in bodyUnits {
            lines += unit
        }
        if hasBody {
            lines += DiffMarking.markedLines("}", marker: marker, indentLevel: headerLevel)
        }
        return lines
    }
}
