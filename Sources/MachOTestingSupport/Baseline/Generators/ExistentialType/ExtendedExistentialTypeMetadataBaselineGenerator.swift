import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ExtendedExistentialTypeMetadataBaseline.swift`.
///
/// `ExtendedExistentialTypeMetadata` is the metadata for a constrained
/// existential carrying primary associated types or `where`-clauses
/// (e.g. `any P<Int>`, `any P where P.Element == Int`). The runtime
/// allocates these on demand via the `swift_getExtendedExistentialType`
/// machinery and there's no static record in `__swift5_types`/2 — so no
/// live carrier is reachable from MachOFile section walks. The Suite
/// asserts the type's structural members behave correctly against a
/// synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum ExtendedExistentialTypeMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ExtendedExistentialTypeMetadata is a runtime-allocated metadata
        // shape with no static section emission. SymbolTestsCore declares
        // primary-associated-type protocols (e.g. ProtocolPrimaryAssociated
        // TypeTest), but the constrained metadata is materialised lazily
        // via `swift_getExtendedExistentialType` — no live carrier is
        // reachable from the static walks. The Suite asserts structural
        // members behave against a synthetic memberwise instance.
        //
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExtendedExistentialTypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExtendedExistentialTypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
