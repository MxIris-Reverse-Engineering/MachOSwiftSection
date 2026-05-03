import Foundation
@testable import MachOTestingSupport

/// Public members of `Sources/MachOSwiftSection/Models/` that are intentionally
/// not under fixture-based test coverage. Each entry MUST carry a human-readable
/// reason. The Coverage Invariant Test (Task 16) treats listed entries as if
/// they had been tested.
enum CoverageAllowlistEntries {
    static let entries: [CoverageAllowlistEntry] = [
        // Populated iteratively by Task 16 once the static-vs-runtime invariant
        // test is run. Reasons fall into a few categories:
        //
        //   - "macro-generated, not visible to scanner": the source declaration
        //     is materialized by a macro (e.g., `@CaseCheckable`,
        //     `@AssociatedValue`, `@MemberwiseInit`) so PublicMemberScanner
        //     cannot see it.
        //
        //   - "needs fixture extension": SymbolTestsCore has no example that
        //     exercises this entity (e.g., a foreign class). Track in Task 17/18
        //     and remove the entry once the fixture grows.
        //
        //   - "MachO-only debug formatter, documented in source": specific
        //     helpers that exist for binary inspection only and have no
        //     ReadingContext mirror (e.g., printf-style address dumpers).
        //
        //   - "synthesized memberwise initializer (visible via @testable)":
        //     a Swift-synthesized initializer for a public struct with no
        //     explicit init. PublicMemberScanner only sees declared `init`
        //     blocks; the Suite reaches the synthesized initializer through
        //     `@testable import MachOSwiftSection`.

        .init(
            typeName: "ProtocolDescriptorRef",
            memberName: "init(storage:)",
            reason: "synthesized memberwise initializer (visible via @testable)"
        ),
    ]

    static var keys: Set<MethodKey> { Set(entries.map(\.key)) }
}
