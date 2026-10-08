import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ClassMetadataBoundsBaseline.swift`.
///
/// `ClassMetadataBounds` is a value type holding three scalars
/// (`negativeSizeInWords`, `positiveSizeInWords`, `immediateMembersOffset`).
/// It's normally constructed via the static factories on
/// `ClassMetadataBoundsProtocol`, not picked from the binary directly.
/// The baseline records only the registered member names; the Suite
/// exercises the type by constructing instances and checking the layout.
package enum ClassMetadataBoundsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in ClassMetadataBounds.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ClassMetadataBounds is a derived type usually built through
        // factory methods on ClassMetadataBoundsProtocol.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ClassMetadataBoundsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ClassMetadataBoundsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
