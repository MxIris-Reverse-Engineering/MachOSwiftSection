/// Renders an `ABIDiff` into a plain-text, `git`-style report:
/// `+` added, `-` removed, `~` modified. A pure `ABIDiff -> String` function —
/// it reads only the names and signatures already on the diff, so it needs no
/// model and no Mach-O.
///
/// This is the lightweight summary renderer. TODO(P2): a structure-driven
/// rendering that reprints the full before/after declarations via
/// `SwiftPrinting` for a true interface-level `+`/`-` diff.
public struct ABIDiffReporter: Sendable {
    public init() {}

    public func report(_ diff: ABIDiff) -> String {
        var sections: [String] = []
        appendContainerSection(&sections, "Types", diff.types)
        appendContainerSection(&sections, "Protocols", diff.protocols)
        appendContainerSection(&sections, "Type extensions", diff.typeExtensions)
        appendContainerSection(&sections, "Protocol extensions", diff.protocolExtensions)
        appendContainerSection(&sections, "Type-alias extensions", diff.typeAliasExtensions)
        appendContainerSection(&sections, "Conformance extensions", diff.conformanceExtensions)
        appendMemberSection(&sections, "Global variables", diff.globalVariables)
        appendMemberSection(&sections, "Global functions", diff.globalFunctions)

        var report = sections.isEmpty ? "No ABI changes." : sections.joined(separator: "\n\n")
        if let diagnostics = diff.diagnostics, !diagnostics.isEmpty {
            report += "\n\n" + warningsSection(diagnostics)
        }
        return report
    }

    /// Identity-key collisions surfaced so the verdict is never quietly weaker
    /// than it looks: a dropped record was not compared, so it can hide a
    /// change (see `ABIKeyCollision`).
    private func warningsSection(_ diagnostics: ABIDiffDiagnostics) -> String {
        var lines = ["Warnings — identity-key collisions (first record kept, later ones not compared):"]
        for (sideName, collisions) in [("old", diagnostics.oldSideKeyCollisions), ("new", diagnostics.newSideKeyCollisions)] {
            for collision in collisions {
                lines.append("  \(sideName) · \(collisionLine(collision))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func collisionLine(_ collision: ABIKeyCollision) -> String {
        let scope = collision.containerName.map { "\($0) · " } ?? ""
        return scope + "dropped: " + collision.droppedSignatures.joined(separator: ", ")
    }

    // MARK: - Sections

    private func appendContainerSection(_ sections: inout [String], _ title: String, _ changes: [ContainerChange]) {
        guard !changes.isEmpty else { return }
        var lines = ["\(title):"]
        for change in changes {
            lines.append("  \(sigil(change.status)) \(change.name)")
            for memberChange in change.memberChanges {
                lines.append("      \(memberLine(memberChange))")
            }
        }
        sections.append(lines.joined(separator: "\n"))
    }

    private func appendMemberSection(_ sections: inout [String], _ title: String, _ changes: [MemberChange]) {
        guard !changes.isEmpty else { return }
        var lines = ["\(title):"]
        for change in changes {
            lines.append("  \(memberLine(change))")
        }
        sections.append(lines.joined(separator: "\n"))
    }

    // MARK: - Lines

    private func memberLine(_ change: MemberChange) -> String {
        let detail: String
        switch change.status {
        case .added:
            detail = change.newSignature ?? change.key.display
        case .removed:
            detail = change.oldSignature ?? change.key.display
        case .modified:
            detail = "\(change.oldSignature ?? change.key.display) → \(change.newSignature ?? change.key.display)"
        }
        return "\(sigil(change.status)) \(detail)"
    }

    private func sigil(_ status: ChangeStatus) -> String {
        switch status {
        case .added: return "+"
        case .removed: return "-"
        case .modified: return "~"
        }
    }
}

private extension ABIKey {
    /// A human-ish fallback when a change carries no signature string.
    var display: String {
        switch self {
        case .mangled(let value): return value
        case .printed(let value): return value
        }
    }
}
