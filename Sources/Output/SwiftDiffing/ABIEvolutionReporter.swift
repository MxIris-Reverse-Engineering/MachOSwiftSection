/// Renders an `ABIEvolution` into a plain-text timeline report. A pure
/// `ABIEvolution -> String` function — like `ABIDiffReporter` it reads only
/// names, signatures and the version axis already on the value.
///
/// Layout: a header naming the axis, a per-transition summary with the
/// additive/breaking verdict, then one section per bucket. Every lineage line
/// starts with a per-version presence bitmap (`●` present, `○` absent) and is
/// followed by its events, phrased against the version labels:
///
/// ```
/// Types:
///   [●●○] SwiftUI.Foo
///       - removed in 26.0
///       [●○○] func bar() -> ()
///           - removed in 18.0
/// ```
///
/// A version whose image carries no local Swift symbols cannot show a member
/// only a non-exported symbol evidences (evolution proposal
/// `evolution-unobservable-presence`): its position reads `◍` where the
/// versions around it both have the member (inferred present) and `◌`
/// otherwise, and a change across such a span is placed `between` the
/// versions that saw it.
///
/// Over groups of images (evolution proposal `image-group-evolution`), the
/// header names each image with the versions holding it, and a declaration
/// that moved between them reads `> moved in 15.0: SwiftUI → SwiftUICore`
/// among its events; the transition summary counts the moves without
/// letting them weigh on the verdict.
public struct ABIEvolutionReporter: Sendable {
    public init() {}

    public func report(_ evolution: ABIEvolution) -> String {
        var sections: [String] = [header(evolution), transitionSummary(evolution)]
        appendContainerSection(&sections, "Types", evolution.types, evolution)
        appendContainerSection(&sections, "Protocols", evolution.protocols, evolution)
        appendContainerSection(&sections, "Type extensions", evolution.typeExtensions, evolution)
        appendContainerSection(&sections, "Protocol extensions", evolution.protocolExtensions, evolution)
        appendContainerSection(&sections, "Type-alias extensions", evolution.typeAliasExtensions, evolution)
        appendContainerSection(&sections, "Conformance extensions", evolution.conformanceExtensions, evolution)
        appendMemberSection(&sections, "Global variables", evolution.globalVariables, evolution)
        appendMemberSection(&sections, "Global functions", evolution.globalFunctions, evolution)
        if evolution.isEmpty {
            sections.append("No ABI changes across the axis.")
        }
        if let keyCollisionsByVersion = evolution.keyCollisionsByVersion {
            sections.append(collisionWarningsSection(keyCollisionsByVersion, evolution))
        }
        if let remangleFallbacksByVersion = evolution.remangleFallbacksByVersion {
            sections.append(remangleFallbackWarningsSection(remangleFallbacksByVersion, evolution))
        }
        return sections.joined(separator: "\n\n")
    }

    /// Identity-key collisions per version, surfaced so a lineage is never
    /// quietly weaker than reported (a dropped record was not compared there).
    private func collisionWarningsSection(_ keyCollisionsByVersion: [[ABIKeyCollision]], _ evolution: ABIEvolution) -> String {
        var lines = ["Warnings — identity-key collisions (first record kept, later ones not compared):"]
        for (versionIndex, collisions) in keyCollisionsByVersion.enumerated() {
            for collision in collisions {
                let scope = collision.containerName.map { "\($0) · " } ?? ""
                lines.append("  \(evolution.versions[versionIndex].label) · \(scope)dropped: \(collision.droppedRecordDescriptions.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Remangle-fallback keys per version — a key that is print-derived rather
    /// than remangled can flip identity across toolchains, so its lineage's
    /// removed+added stories deserve a skeptical read (see
    /// `ABIRemangleFallback`).
    private func remangleFallbackWarningsSection(_ remangleFallbacksByVersion: [[ABIRemangleFallback]], _ evolution: ABIEvolution) -> String {
        var lines = ["Warnings — remangle-fallback keys (print-derived identity; removed+added may be an identity flip across toolchains):"]
        for (versionIndex, fallbacks) in remangleFallbacksByVersion.enumerated() {
            for fallback in fallbacks {
                let scope = fallback.containerName.map { "\($0) · " } ?? ""
                lines.append("  \(evolution.versions[versionIndex].label) · \(scope)\(fallback.signature)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Just the header + per-transition summary, for `--summary-only`.
    public func summary(_ evolution: ABIEvolution) -> String {
        header(evolution) + "\n\n" + transitionSummary(evolution)
    }

    // MARK: - Header & summary

    /// The axis line, and — for an evolution over groups of images
    /// (evolution proposal `image-group-evolution`) — each image with the
    /// versions holding it, right under it.
    private func header(_ evolution: ABIEvolution) -> String {
        let axis = evolution.versions.map(\.label).joined(separator: " → ")
        var lines = ["ABI evolution across \(evolution.versions.count) versions: \(axis)"]
        if let imagePresences = evolution.imagePresences {
            lines.append("Image group:")
            for imagePresence in imagePresences {
                lines.append("  \(bitmap(imagePresence.presence, nil)) \(imagePresence.imageName)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func transitionSummary(_ evolution: ABIEvolution) -> String {
        let compatibilities = evolution.transitionCompatibilities
        var lines = ["Transitions:"]
        for versionIndex in 1 ..< evolution.versions.count {
            let counts = eventCounts(evolution, at: versionIndex)
            let step = "\(evolution.versions[versionIndex - 1].label) → \(evolution.versions[versionIndex].label)"
            if counts.total == 0, counts.moved == 0 {
                lines.append("  \(step): no changes")
            } else {
                var parts: [String] = []
                if counts.added > 0 { parts.append("\(counts.added) added") }
                if counts.removed > 0 { parts.append("\(counts.removed) removed") }
                if counts.modified > 0 { parts.append("\(counts.modified) modified") }
                // Moves between the images of a group never weigh on the
                // verdict (see `ImageMove`).
                if counts.moved > 0 { parts.append("\(counts.moved) moved") }
                let verdict = compatibilities[versionIndex - 1] == .breaking ? "ABI-breaking" : "additive"
                lines.append("  \(step): " + (parts + [verdict]).joined(separator: " · "))
                // A change first observed here may have happened in the
                // versions before, which could not show it.
                for (earliestVersionIndex, spanningCount) in counts.spanningCountsByEarliestVersionIndex.sorted(by: { $0.key < $1.key }) {
                    let span = "between \(evolution.versions[earliestVersionIndex - 1].label) and \(evolution.versions[versionIndex].label)"
                    lines.append("    (\(spanningCount) of them happened somewhere \(span): the versions in between could not show them)")
                }
            }
        }
        if let firstBreakingVersionIndex = evolution.firstBreakingVersionIndex {
            let step = "\(evolution.versions[firstBreakingVersionIndex - 1].label) → \(evolution.versions[firstBreakingVersionIndex].label)"
            lines.append("First ABI-breaking transition: \(step)")
        }
        if let versionIndicesWithoutLocalSwiftSymbols = evolution.versionIndicesWithoutLocalSwiftSymbols {
            let labels = evolution.versions.labels(ofVersionsAt: versionIndicesWithoutLocalSwiftSymbols)
            lines.append("No local Swift symbols, so non-exported members cannot be seen: \(labels) (◍ inferred present, ◌ not observable)")
        }
        return lines.joined(separator: "\n")
    }

    /// The changes first observed at `versionIndex`: the events by status,
    /// their total, the moves between images, and how many of either span
    /// versions that could not show them, by the first of those versions.
    private func eventCounts(_ evolution: ABIEvolution, at versionIndex: Int) -> (added: Int, removed: Int, modified: Int, total: Int, moved: Int, spanningCountsByEarliestVersionIndex: [Int: Int]) {
        var added = 0, removed = 0, modified = 0, moved = 0
        var spanningCountsByEarliestVersionIndex: [Int: Int] = [:]
        func count(_ events: [LineageEvent], _ imageMoves: [ImageMove]?) {
            for event in events where event.versionIndex == versionIndex {
                switch event.status {
                case .added: added += 1
                case .removed: removed += 1
                case .modified: modified += 1
                }
                if let earliestVersionIndex = event.earliestVersionIndex {
                    spanningCountsByEarliestVersionIndex[earliestVersionIndex, default: 0] += 1
                }
            }
            for imageMove in imageMoves ?? [] where imageMove.versionIndex == versionIndex {
                moved += 1
                if let earliestVersionIndex = imageMove.earliestVersionIndex {
                    spanningCountsByEarliestVersionIndex[earliestVersionIndex, default: 0] += 1
                }
            }
        }
        for lineage in evolution.allContainerLineages {
            count(lineage.events, lineage.imageMoves)
            for memberLineage in lineage.memberLineages {
                count(memberLineage.events, memberLineage.imageMoves)
            }
        }
        for lineage in evolution.allGlobalLineages {
            count(lineage.events, lineage.imageMoves)
        }
        return (added, removed, modified, added + removed + modified, moved, spanningCountsByEarliestVersionIndex)
    }

    // MARK: - Sections

    private func appendContainerSection(
        _ sections: inout [String],
        _ title: String,
        _ lineages: [ContainerLineage],
        _ evolution: ABIEvolution
    ) {
        guard !lineages.isEmpty else { return }
        var lines = ["\(title):"]
        for lineage in lineages {
            lines.append("  \(bitmap(lineage.presence, lineage.presenceStates)) \(lineage.name)")
            for changeLine in changeLines(lineage.events, lineage.imageMoves, evolution, signatures: false) {
                lines.append("      \(changeLine)")
            }
            for spanLine in unobservedSpanLines(lineage.presenceStates, events: lineage.events, evolution) {
                lines.append("      \(spanLine)")
            }
            for memberLineage in lineage.memberLineages {
                lines.append("      \(bitmap(memberLineage.presence, memberLineage.presenceStates)) \(latestSignature(memberLineage))")
                for changeLine in changeLines(memberLineage.events, memberLineage.imageMoves, evolution, signatures: true) {
                    lines.append("          \(changeLine)")
                }
                for spanLine in unobservedSpanLines(memberLineage.presenceStates, events: memberLineage.events, evolution) {
                    lines.append("          \(spanLine)")
                }
            }
        }
        sections.append(lines.joined(separator: "\n"))
    }

    private func appendMemberSection(
        _ sections: inout [String],
        _ title: String,
        _ lineages: [MemberLineage],
        _ evolution: ABIEvolution
    ) {
        guard !lineages.isEmpty else { return }
        var lines = ["\(title):"]
        for lineage in lineages {
            lines.append("  \(bitmap(lineage.presence, lineage.presenceStates)) \(latestSignature(lineage))")
            for changeLine in changeLines(lineage.events, lineage.imageMoves, evolution, signatures: true) {
                lines.append("      \(changeLine)")
            }
            for spanLine in unobservedSpanLines(lineage.presenceStates, events: lineage.events, evolution) {
                lines.append("      \(spanLine)")
            }
        }
        sections.append(lines.joined(separator: "\n"))
    }

    // MARK: - Lines

    /// A lineage's events and moves between images, ordered by the version
    /// each was first observed at — the events of a version before its moves:
    /// `> moved in 15.0: SwiftUI → SwiftUICore`.
    private func changeLines(_ events: [LineageEvent], _ imageMoves: [ImageMove]?, _ evolution: ABIEvolution, signatures: Bool) -> [String] {
        let eventLines = events.map { event in
            (versionIndex: event.versionIndex, isMove: false, line: eventLine(event, evolution, signatures: signatures))
        }
        let moveLines = (imageMoves ?? []).map { imageMove in
            (versionIndex: imageMove.versionIndex, isMove: true, line: "> " + imageMove.phrase(on: evolution.versions))
        }
        return (eventLines + moveLines).enumerated()
            .sorted { left, right in
                (left.element.versionIndex, left.element.isMove ? 1 : 0, left.offset) < (right.element.versionIndex, right.element.isMove ? 1 : 0, right.offset)
            }
            .map(\.element.line)
    }

    /// The lineage's most recent rendering: the last event's signature (new
    /// side preferred), or — for a lineage without events, kept for its
    /// unobservable versions — the signature it carries.
    private func latestSignature(_ lineage: MemberLineage) -> String {
        for event in lineage.events.reversed() {
            if let signature = event.newSignature ?? event.oldSignature {
                return signature
            }
        }
        return lineage.latestSignature ?? displayText(of: lineage.key)
    }

    /// One event phrased against the axis. `signatures: false` keeps container
    /// events to the bare phrase (containers carry no signature; their name is
    /// already on the lineage line).
    private func eventLine(_ event: LineageEvent, _ evolution: ABIEvolution, signatures: Bool) -> String {
        let placement = event.placement(on: evolution.versions)
        switch event.status {
        case .added:
            return "+ added \(placement)"
        case .removed:
            return "- removed \(placement)"
        case .modified:
            guard signatures, let oldSignature = event.oldSignature, let newSignature = event.newSignature else {
                return "~ modified \(placement)"
            }
            return "~ modified \(placement): \(oldSignature) → \(newSignature)"
        }
    }

    /// The spans of versions that could not show the declaration and that
    /// say something: inferred present, or leaving a bound unknown without an
    /// event spanning them (``UnobservedSpan/isPhrasedAsNotObservable(spannedFirstIndices:)``).
    private func unobservedSpanLines(_ presenceStates: [LineagePresenceState]?, events: [LineageEvent], _ evolution: ABIEvolution) -> [String] {
        guard let presenceStates else { return [] }
        let spannedFirstIndices = Set(events.compactMap(\.earliestVersionIndex))
        return presenceStates.unobservedSpans.compactMap { span in
            let labels = evolution.versions.labels(spanning: span.versionIndices)
            if span.state == .inferredPresent {
                return "◍ inferred present in \(labels)"
            } else if span.isPhrasedAsNotObservable(spannedFirstIndices: spannedFirstIndices) {
                return "◌ not observable in \(labels)"
            } else {
                return nil
            }
        }
    }

    private func bitmap(_ presence: [Bool], _ presenceStates: [LineagePresenceState]?) -> String {
        guard let presenceStates else {
            return "[" + presence.map { $0 ? "●" : "○" }.joined() + "]"
        }
        return "[" + presenceStates.map { state in
            switch state {
            case .present: "●"
            case .absent: "○"
            case .inferredPresent: "◍"
            case .unobservable: "◌"
            }
        }.joined() + "]"
    }

    private func displayText(of key: ABIKey) -> String {
        switch key {
        case .mangled(let value): return value
        case .printed(let value): return value
        }
    }
}
