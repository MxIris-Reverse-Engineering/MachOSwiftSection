import Foundation
import Semantic

/// One piece of what a request produces.
///
/// Printed, every piece is followed by a newline — the one `print` adds, and
/// the one a snapshot's JSON has always been followed by. A host that collects
/// the pieces into a file reproduces `swift-section`'s stdout by doing the same.
public enum SwiftSectionProduct: Sendable {
    /// Rendered declarations (`dump`, `interface`, `objc dump`,
    /// `objc interface`), carrying the semantic types a terminal colors by.
    case declarations(SemanticString)
    /// Plain text: a report, JSON, a listing line.
    case text(String)
    /// An annotated interface, whose lines a terminal colors by their
    /// annotation; ``InterfaceAnnotationStyle/lineKinds(of:)`` tells how.
    case annotatedInterface(String, style: InterfaceAnnotationStyle)
    /// Raw bytes: a snapshot document's JSON.
    case data(Data)
}

/// Which annotations an annotated interface carries.
public enum InterfaceAnnotationStyle: Sendable, Hashable {
    /// `diff --interface`: `+` / `-` line prefixes. A unified diff also has two
    /// file-header lines and `@@` hunk headers.
    case diff(isUnifiedDiff: Bool)
    /// `evolution --interface`: trailing `// [...]` lifecycle annotations, and
    /// legend and warning comments at column 0.
    case evolution
}

/// What one line of an annotated interface reads as.
public enum AnnotatedLineKind: Sendable, Hashable {
    case added
    case removed
    case modified
    /// A unified diff's file and hunk headers; an evolution interface's legend
    /// and warnings.
    case header
    case plain
}

extension InterfaceAnnotationStyle {
    /// The rule `swift-section` colors an annotated interface by, public so
    /// that every host colors alike: one kind per line of `text`, split on
    /// "\n" with empty lines kept.
    public func lineKinds(of text: String) -> [AnnotatedLineKind] {
        text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { lineIndex, line in
            lineKind(of: line, at: lineIndex)
        }
    }

    private func lineKind(of line: Substring, at lineIndex: Int) -> AnnotatedLineKind {
        switch self {
        case .diff(let isUnifiedDiff):
            // In a unified diff the first two lines are the `--- old` /
            // `+++ new` file headers and `@@ … @@` lines are hunk headers.
            // They are told apart by position and prefix, so that an added or
            // removed content line that happens to begin with `++` or `--` is
            // never mistaken for a file header.
            if isUnifiedDiff, lineIndex < 2 {
                return .header
            } else if isUnifiedDiff, line.hasPrefix("@@") {
                return .header
            } else if line.hasPrefix("+") {
                return .added
            } else if line.hasPrefix("-") {
                return .removed
            } else {
                return .plain
            }
        case .evolution:
            if line.hasPrefix("//") {
                // The legend and warnings blocks sit at column 0.
                return .header
            } else if let annotationRange = line.range(of: "// [") {
                // A trailing lifecycle annotation, or an overflow annotation on
                // its own (indented) line. Classified by the annotation text
                // only, so that a declaration whose name mentions these words
                // stays plain.
                let annotation = line[annotationRange.lowerBound...]
                if annotation.contains("removed in") {
                    return .removed
                } else if annotation.contains("modified in") {
                    return .modified
                } else {
                    return .added
                }
            } else {
                return .plain
            }
        }
    }
}
