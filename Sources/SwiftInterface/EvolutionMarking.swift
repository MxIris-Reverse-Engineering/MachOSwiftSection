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

    /// Where a unit's annotation attaches. The declaration line is what the
    /// annotation describes, and the two unit shapes carry it at opposite
    /// ends: a member's attributes print inline, so its FIRST line is the
    /// declaration (and a computed property's accessor block trails it — the
    /// annotation must not sink to the block's closing brace); a container
    /// header's attribute lines each precede the declaration, so its LAST
    /// line is the one carrying the opening brace.
    enum AnnotationAnchor {
        case firstLine
        case lastLine
    }

    /// Splits one rendered unit (a member, a container header, a closing brace
    /// — no indentation, no leading/trailing newline of its own) into per-line
    /// ``EvolutionLine``s, attaching the annotation to the `anchor` line.
    /// Empty `source` produces `[]` so empty units never leave a stray
    /// annotation.
    static func annotatedLines(
        _ source: SemanticString,
        annotation: EvolutionAnnotation?,
        indentLevel: Int,
        anchor: AnnotationAnchor
    ) -> [EvolutionLine] {
        if source.string.isEmpty { return [] }
        let lines = DiffMarking.splitIntoLines(source.components)
        let anchorIndex = anchor == .firstLine ? 0 : lines.count - 1
        return lines.enumerated().map { lineIndex, line in
            EvolutionLine(
                content: SemanticString(components: line),
                indentLevel: indentLevel,
                annotation: lineIndex == anchorIndex ? annotation : nil
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

    // MARK: - Availability attributes

    /// The genuine `@available` attribute expressing a lifecycle, or `nil`
    /// when the facts are not FULLY expressible as one syntactically valid
    /// attribute — the attribute is emitted only when it tells the whole
    /// presence story, the bitmap comment stays the carrier of everything
    /// else (evolution proposal draft-evolution-interface-available-annotations):
    ///
    /// - The presence bitmap must be a single interval (`○ᵃ●ᵇ○ᶜ`); a
    ///   disappeared-and-returned shape (`●○●`) fits no single attribute.
    /// - `introduced:` exists only when the declaration is absent at the
    ///   axis start (present-from-the-first-version means "predates the
    ///   axis", which is not an introduction fact); `obsoleted:` only when
    ///   it is absent at the axis end.
    /// - Every involved version label must parse as a dotted numeric version
    ///   (`26.0`, `18.5.1`) — a file-name fallback label cannot become a
    ///   version literal.
    /// - Modified events never participate: `@available` has no vocabulary
    ///   for them, so a modified-throughout lifecycle yields `nil`.
    ///
    /// The facts are axis-resolution: `introduced:` names the first axis
    /// point carrying the declaration, not necessarily the OS release that
    /// really introduced it (the legend states this once per document).
    static func availabilityAttributeText(
        for annotation: EvolutionAnnotation,
        versions: [ABIVersionDescriptor],
        platform: String
    ) -> String? {
        guard annotation.presence.count == versions.count else { return nil }
        guard let interval = singlePresenceInterval(annotation.presence) else { return nil }
        var clauses: [String] = []
        if interval.firstPresentIndex > 0 {
            guard let introducedVersion = availabilityVersion(fromLabel: versions[interval.firstPresentIndex].label) else { return nil }
            clauses.append("introduced: \(introducedVersion)")
        }
        if let firstAbsentIndexAfterPresence = interval.firstAbsentIndexAfterPresence {
            guard let obsoletedVersion = availabilityVersion(fromLabel: versions[firstAbsentIndexAfterPresence].label) else { return nil }
            clauses.append("obsoleted: \(obsoletedVersion)")
        }
        guard !clauses.isEmpty else { return nil }
        return "@available(\(platform), \(clauses.joined(separator: ", ")))"
    }

    /// Prepends the availability attribute as its own line above a unit's
    /// lines. An empty unit stays empty — no stray attribute, mirroring
    /// `annotatedLines`' empty-source rule. The attribute line carries no
    /// annotation of its own (the bitmap comment stays anchored on the
    /// declaration line it has always lived on).
    static func prependingAvailabilityAttribute(
        _ attributeText: String?,
        to lines: [EvolutionLine],
        indentLevel: Int
    ) -> [EvolutionLine] {
        guard let attributeText, !lines.isEmpty else { return lines }
        var attributeContent = SemanticString()
        attributeContent.append(attributeText, type: .keyword)
        return [EvolutionLine(content: attributeContent, indentLevel: indentLevel, annotation: nil)] + lines
    }

    /// The single presence interval `○ᵃ●ᵇ○ᶜ` (a, c ≥ 0, b ≥ 1), or `nil`
    /// when the bitmap holds no presence at all or more than one presence
    /// run. `firstAbsentIndexAfterPresence` is the removal transition's
    /// version index, `nil` when the declaration is still present at the
    /// axis end.
    private static func singlePresenceInterval(
        _ presence: [Bool]
    ) -> (firstPresentIndex: Int, firstAbsentIndexAfterPresence: Int?)? {
        guard let firstPresentIndex = presence.firstIndex(of: true) else { return nil }
        guard let firstAbsentIndexAfterPresence = presence[firstPresentIndex...].firstIndex(of: false) else {
            return (firstPresentIndex, nil)
        }
        guard !presence[firstAbsentIndexAfterPresence...].contains(true) else { return nil }
        return (firstPresentIndex, firstAbsentIndexAfterPresence)
    }

    /// A label usable as an `@available` version literal: one to three
    /// dot-separated runs of ASCII digits (`26`, `18.5`, `18.5.1`). Returned
    /// verbatim on success.
    static func availabilityVersion(fromLabel label: String) -> String? {
        let components = label.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count) else { return nil }
        for component in components {
            guard !component.isEmpty, component.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        }
        return label
    }

    // MARK: - Document rendering

    /// The final annotated interface: legend header, the blocks separated by
    /// blank lines, and — when the evolution carries diagnostics — a warnings
    /// tail mirroring `ABIEvolutionReporter`'s two warnings sections as
    /// comments (surfaced, not silent).
    static func renderInterface(
        blocks: [[EvolutionLine]],
        evolution: ABIEvolution,
        availabilityAnnotationPlatform: String? = nil
    ) -> SemanticString {
        var result = legendLines(for: evolution, availabilityAnnotationPlatform: availabilityAnnotationPlatform)
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
    /// version labels — the key to reading every `[●●○]` in the body. With
    /// availability attributes enabled, a third line states their semantic
    /// resolution once, so no attribute in the body overclaims.
    static func legendLines(for evolution: ABIEvolution, availabilityAnnotationPlatform: String? = nil) -> SemanticString {
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
        if let availabilityAnnotationPlatform {
            result.append("\n", type: .standard)
            result.append(
                "// @available(\(availabilityAnnotationPlatform), …) attributes are axis-resolution facts: introduced: names the first axis point carrying a declaration, obsoleted: the first axis point without it — not necessarily the exact release versions.",
                type: .comment
            )
        }
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

        var lines = EvolutionMarking.annotatedLines(header.appending(opening), annotation: annotation, indentLevel: headerLevel, anchor: .lastLine)
        for unit in bodyUnits {
            lines += unit
        }
        if hasBody {
            lines += EvolutionMarking.annotatedLines("}", annotation: nil, indentLevel: headerLevel, anchor: .lastLine)
        }
        return lines
    }
}
