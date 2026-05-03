import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/CanonicalSpecializedMetadataAccessorsListEntryBaseline.swift`.
///
/// `CanonicalSpecializedMetadataAccessorsListEntry` is a trailing-objects
/// payload appended to descriptors that declare canonical metadata
/// prespecializations (the `hasCanonicalMetadataPrespecializations` bit).
/// The `SymbolTestsCore` fixture does NOT use any `@_specialize`
/// prespecialization directives, so no descriptor in the fixture surfaces a
/// non-empty `canonicalSpecializedMetadataAccessors` array. Consequently we
/// emit only the registered member names — the structural layout is exercised
/// indirectly by `Class.canonicalSpecializedMetadataAccessors` reads when
/// the fixture is extended with prespecialized types.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum CanonicalSpecializedMetadataAccessorsListEntryBaselineGenerator {
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
        // SymbolTestsCore declares no canonical-metadata prespecializations,
        // so no live entry is materialised. The companion Suite asserts the
        // type's structural members exist; runtime payloads will be exercised
        // when prespecialized types are added to the fixture.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum CanonicalSpecializedMetadataAccessorsListEntryBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("CanonicalSpecializedMetadataAccessorsListEntryBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
