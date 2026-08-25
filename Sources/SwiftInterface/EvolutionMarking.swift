import Foundation
import SwiftDiffing
import Semantic

/// The format layer of the annotated evolution interface: how an
/// ``EvolutionAnnotation`` becomes a trailing comment, and how the renderer's
/// block-grouped `[[EvolutionLine]]` stream becomes the final `SemanticString`
/// (legend header, per-block annotation-column alignment, warnings tail).
///
/// Pure functions of their inputs — no renderer state — so every formatting
/// rule is unit-testable against synthetic lines, following the
/// `DiffMarking` / `DiffContainerAssembler` precedent.
enum EvolutionMarking {
    /// Structural indentation width per level, matching `DiffMarking`.
    static let indentWidth = 4

    /// The column cap for trailing-annotation alignment. Within one top-level
    /// block, annotations align at `min(cap, longest annotated code line + 2)`;
    /// a line whose code runs past the resolved column pushes its annotation
    /// onto its own comment line instead (indented one level deeper).
    static let annotationColumnCap = 72

    /// The minimum gap between a line's code and its trailing annotation.
    static let annotationGutterWidth = 2

    // MARK: - Line classification

    /// Splits one rendered unit (a member, a container header, a closing brace
    /// — no indentation, no leading/trailing newline of its own) into per-line
    /// ``EvolutionLine``s. The annotation is attached to the unit's LAST line:
    /// a member's declaration line (comment lines the printer emits above it
    /// stay bare), a container header's `{` line. Empty `source` produces `[]`
    /// so empty units never leave a stray annotation.
    static func annotatedLines(_ source: SemanticString, annotation: EvolutionAnnotation?, indentLevel: Int) -> [EvolutionLine] {
        if source.string.isEmpty { return [] }
        let lines = DiffMarking.splitIntoLines(source.components)
        return lines.enumerated().map { lineIndex, line in
            EvolutionLine(
                content: SemanticString(components: line),
                indentLevel: indentLevel,
                annotation: lineIndex == lines.count - 1 ? annotation : nil
            )
        }
    }

    // MARK: - Annotation text

    /// `[●●○]` — one position per version on the axis.
    static func bitmap(_ presence: [Bool]) -> String {
        "[" + presence.map { $0 ? "●" : "○" }.joined() + "]"
    }

    /// One event phrased against the version axis. A modified event whose old
    /// and new signatures render identically (an ABI payload change with no
    /// signature-visible difference — accessor set, symbolic identity) keeps
    /// the bare phrase: an identical `A → A` arrow is pure noise, the same
    /// reasoning as the two-sided renderer's identical-rendering collapse.
    static func phrase(for event: LineageEvent, versions: [ABIVersionDescriptor]) -> String {
        let label = versions.indices.contains(event.versionIndex)
            ? versions[event.versionIndex].label
            : "v\(event.versionIndex + 1)"
        switch event.status {
        case .added:
            return "added in \(label)"
        case .removed:
            return "removed in \(label)"
        case .modified:
            guard let oldSignature = event.oldSignature, let newSignature = event.newSignature, oldSignature != newSignature else {
                return "modified in \(label)"
            }
            return "modified in \(label): \(oldSignature) → \(newSignature)"
        }
    }

    /// The full trailing comment: `// [●●○] removed in 26.0`, multiple events
    /// joined by ` · `.
    static func annotationText(for annotation: EvolutionAnnotation, versions: [ABIVersionDescriptor]) -> String {
        var text = "// " + bitmap(annotation.presence)
        let phrases = annotation.events.map { phrase(for: $0, versions: versions) }
        if !phrases.isEmpty {
            text += " " + phrases.joined(separator: " · ")
        }
        return text
    }

    // MARK: - Document rendering

    /// The final annotated interface: legend header, the blocks separated by
    /// blank lines, and — when the evolution carries diagnostics — a warnings
    /// tail mirroring `ABIEvolutionReporter`'s two warnings sections as
    /// comments (surfaced, not silent).
    static func renderInterface(blocks: [[EvolutionLine]], evolution: ABIEvolution) -> SemanticString {
        var result = legendLines(for: evolution)
        for block in blocks {
            let renderedBlock = renderBlock(block, versions: evolution.versions)
            if renderedBlock.string.isEmpty { continue }
            result.append("\n\n", type: .standard)
            result.append(renderedBlock)
        }
        if let warnings = warningsLines(for: evolution) {
            result.append("\n\n", type: .standard)
            result.append(warnings)
        }
        return result
    }

    /// Two comment lines naming the axis and mapping bitmap positions to
    /// version labels — the key to reading every `[●●○]` in the body.
    static func legendLines(for evolution: ABIEvolution) -> SemanticString {
        let labels = evolution.versions.map(\.label)
        var result = SemanticString()
        result.append(
            "// Swift ABI evolution across \(labels.count) versions: \(labels.joined(separator: " → "))",
            type: .comment
        )
        result.append("\n", type: .standard)
        result.append(
            "// Bitmap positions: " + labels.enumerated().map { "[\($0 + 1)] \($1)" }.joined(separator: "  "),
            type: .comment
        )
        return result
    }

    /// One top-level block. Trailing annotations align on a per-block column:
    /// `min(annotationColumnCap, widest annotated code line + gutter)`. A line
    /// whose code cannot leave the gutter before the resolved column emits its
    /// annotation on the following line instead, indented one level deeper
    /// than the declaration it describes. Blank content lines emit nothing
    /// (no indentation, no trailing whitespace), matching `DiffMarking`'s
    /// blank-line rule.
    static func renderBlock(_ block: [EvolutionLine], versions: [ABIVersionDescriptor]) -> SemanticString {
        let annotatedWidths = block.compactMap { line in
            line.annotation != nil ? codeWidth(of: line) : nil
        }
        let annotationColumn = min(annotationColumnCap, (annotatedWidths.max() ?? 0) + annotationGutterWidth)

        var result = SemanticString()
        var hasEmittedLine = false
        for line in block {
            if hasEmittedLine {
                result.append("\n", type: .standard)
            }
            hasEmittedLine = true

            let lineHasContent = line.content.components.contains { !$0.string.allSatisfy(\.isWhitespace) }
            if lineHasContent {
                result.append(String(repeating: " ", count: max(0, line.indentLevel) * indentWidth), type: .standard)
                result.append(line.content)
            }

            guard let annotation = line.annotation else { continue }
            let text = annotationText(for: annotation, versions: versions)
            let width = codeWidth(of: line)
            if width + annotationGutterWidth <= annotationColumn {
                result.append(String(repeating: " ", count: annotationColumn - width), type: .standard)
                result.append(text, type: .comment)
            } else {
                result.append("\n", type: .standard)
                result.append(String(repeating: " ", count: (max(0, line.indentLevel) + 1) * indentWidth), type: .standard)
                result.append(text, type: .comment)
            }
        }
        return result
    }

    /// The rendered width of a line's code portion (indentation + content).
    private static func codeWidth(of line: EvolutionLine) -> Int {
        max(0, line.indentLevel) * indentWidth + line.content.string.count
    }

    /// The diagnostics tail, or `nil` when the evolution carries none. Wording
    /// mirrors `ABIEvolutionReporter`'s warnings sections so both views tell
    /// the same story.
    static func warningsLines(for evolution: ABIEvolution) -> SemanticString? {
        var lines: [String] = []
        if let keyCollisionsByVersion = evolution.keyCollisionsByVersion {
            lines.append("// Warnings — identity-key collisions (first record kept, later ones not compared):")
            for (versionIndex, collisions) in keyCollisionsByVersion.enumerated() {
                for collision in collisions {
                    let scope = collision.containerName.map { "\($0) · " } ?? ""
                    lines.append("//   \(evolution.versions[versionIndex].label) · \(scope)dropped: \(collision.droppedSignatures.joined(separator: ", "))")
                }
            }
        }
        if let remangleFallbacksByVersion = evolution.remangleFallbacksByVersion {
            lines.append("// Warnings — remangle-fallback keys (print-derived identity; removed+added may be an identity flip across toolchains):")
            for (versionIndex, fallbacks) in remangleFallbacksByVersion.enumerated() {
                for fallback in fallbacks {
                    let scope = fallback.containerName.map { "\($0) · " } ?? ""
                    lines.append("//   \(evolution.versions[versionIndex].label) · \(scope)\(fallback.signature)")
                }
            }
        }
        guard !lines.isEmpty else { return nil }
        var result = SemanticString()
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                result.append("\n", type: .standard)
            }
            result.append(line, type: .comment)
        }
        return result
    }
}

/// Assembles a container declaration (struct / class / enum / protocol /
/// extension) into ONE flat line list from its header, the container-level
/// annotation, and its already-classified body units — the evolution analogue
/// of `DiffContainerAssembler`. The annotation lands on the header's last line
/// (the one carrying the opening brace); the closing brace carries none. An
/// empty body renders inline as ` {}` with no closing-brace line.
enum EvolutionContainerAssembler {
    static func assemble(
        header: SemanticString,
        annotation: EvolutionAnnotation?,
        bodyUnits: [[EvolutionLine]],
        level: Int
    ) -> [EvolutionLine] {
        let hasBody = !bodyUnits.isEmpty
        let opening = hasBody ? " {" : " {}"
        let headerLevel = level - 1

        var lines = EvolutionMarking.annotatedLines(header.appending(opening), annotation: annotation, indentLevel: headerLevel)
        for unit in bodyUnits {
            lines += unit
        }
        if hasBody {
            lines += EvolutionMarking.annotatedLines("}", annotation: nil, indentLevel: headerLevel)
        }
        return lines
    }
}
