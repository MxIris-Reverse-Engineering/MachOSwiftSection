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
                lines.append("  \(evolution.versions[versionIndex].label) · \(scope)dropped: \(collision.droppedSignatures.joined(separator: ", "))")
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

    private func header(_ evolution: ABIEvolution) -> String {
        let axis = evolution.versions.map(\.label).joined(separator: " → ")
        return "ABI evolution across \(evolution.versions.count) versions: \(axis)"
    }

    private func transitionSummary(_ evolution: ABIEvolution) -> String {
        let compatibilities = evolution.transitionCompatibilities
        var lines = ["Transitions:"]
        for versionIndex in 1 ..< evolution.versions.count {
            let counts = eventCounts(evolution, at: versionIndex)
            let step = "\(evolution.versions[versionIndex - 1].label) → \(evolution.versions[versionIndex].label)"
            if counts.total == 0 {
                lines.append("  \(step): no changes")
            } else {
                var parts: [String] = []
                if counts.added > 0 { parts.append("\(counts.added) added") }
                if counts.removed > 0 { parts.append("\(counts.removed) removed") }
                if counts.modified > 0 { parts.append("\(counts.modified) modified") }
                let verdict = compatibilities[versionIndex - 1] == .breaking ? "ABI-breaking" : "additive"
                lines.append("  \(step): " + (parts + [verdict]).joined(separator: " · "))
            }
        }
        if let firstBreakingVersionIndex = evolution.firstBreakingVersionIndex {
            let step = "\(evolution.versions[firstBreakingVersionIndex - 1].label) → \(evolution.versions[firstBreakingVersionIndex].label)"
            lines.append("First ABI-breaking transition: \(step)")
        }
        return lines.joined(separator: "\n")
    }

    private func eventCounts(_ evolution: ABIEvolution, at versionIndex: Int) -> (added: Int, removed: Int, modified: Int, total: Int) {
        var added = 0, removed = 0, modified = 0
        func count(_ events: [LineageEvent]) {
            for event in events where event.versionIndex == versionIndex {
                switch event.status {
                case .added: added += 1
                case .removed: removed += 1
                case .modified: modified += 1
                }
            }
        }
        for lineage in evolution.allContainerLineages {
            count(lineage.events)
            for memberLineage in lineage.memberLineages {
                count(memberLineage.events)
            }
        }
        for lineage in evolution.allGlobalLineages {
            count(lineage.events)
        }
        return (added, removed, modified, added + removed + modified)
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
            lines.append("  \(bitmap(lineage.presence)) \(lineage.name)")
            for event in lineage.events {
                lines.append("      \(eventLine(event, evolution, signatures: false))")
            }
            for memberLineage in lineage.memberLineages {
                lines.append("      \(bitmap(memberLineage.presence)) \(latestSignature(memberLineage))")
                for event in memberLineage.events {
                    lines.append("          \(eventLine(event, evolution, signatures: true))")
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
            lines.append("  \(bitmap(lineage.presence)) \(latestSignature(lineage))")
            for event in lineage.events {
                lines.append("      \(eventLine(event, evolution, signatures: true))")
            }
        }
        sections.append(lines.joined(separator: "\n"))
    }

    // MARK: - Lines

    /// The lineage's most recent rendering: the last event's signature (new
    /// side preferred) — every lineage has at least one event by construction.
    private func latestSignature(_ lineage: MemberLineage) -> String {
        for event in lineage.events.reversed() {
            if let signature = event.newSignature ?? event.oldSignature {
                return signature
            }
        }
        return displayText(of: lineage.key)
    }

    /// One event phrased against the axis. `signatures: false` keeps container
    /// events to the bare phrase (containers carry no signature; their name is
    /// already on the lineage line).
    private func eventLine(_ event: LineageEvent, _ evolution: ABIEvolution, signatures: Bool) -> String {
        let label = evolution.versions[event.versionIndex].label
        switch event.status {
        case .added:
            return "+ added in \(label)"
        case .removed:
            return "- removed in \(label)"
        case .modified:
            guard signatures, let oldSignature = event.oldSignature, let newSignature = event.newSignature else {
                return "~ modified in \(label)"
            }
            return "~ modified in \(label): \(oldSignature) → \(newSignature)"
        }
    }

    private func bitmap(_ presence: [Bool]) -> String {
        "[" + presence.map { $0 ? "●" : "○" }.joined() + "]"
    }

    private func displayText(of key: ABIKey) -> String {
        switch key {
        case .mangled(let value): return value
        case .printed(let value): return value
        }
    }
}
